#!/usr/bin/perl
package IkiWiki::Plugin::epub_field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::epub_field - field parser for EPUB files

=head1 VERSION

This describes version B<0.20120105> of IkiWiki::Plugin::epub_field

=cut

our $VERSION = '0.20120105';

=head1 PREREQUISITES

    IkiWiki
    Archive::Zip

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use XML::LibXML;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

my %Cache = ();

sub import {
	hook(type => "getsetup", id => "epub_field", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'epub_field',
	get_value=>\&get_epub_value);

}

#-------------------------------------------------------
# Hooks
#-------------------------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 1,
		},
} # getsetup

#-------------------------------------------------------
# field functions
#-------------------------------------------------------
sub get_epub_value ($$) {
    my $field_name = shift;
    my $page = shift;

    if (!exists $Cache{$page})
    {
	my $values = parse_epub_vars(page=>$page);
	if (defined $values)
	{
	    $Cache{$page} = $values;
	}
    }
    if (exists $Cache{$page}{$field_name})
    {
	return $Cache{$page}{$field_name};
    }
    return undef;
} # get_epub_value

#-------------------------------------------------------
# Private functions
#-------------------------------------------------------
sub parse_epub_vars ($$) {
    my %params = @_;
    my $page = $params{page};

    my $file = $pagesources{$page};
    return undef if (!$file);

    my $page_type = pagetype($file);
    if ($file =~ /\.epub$/i or ($page_type and $page_type eq 'epub'))
    {
        my $fullname = srcfile($file, 1);
        return undef if (!$fullname);

	my %values = ();
	my $zip = Archive::Zip->new();
	my $status = $zip->read( $fullname );
	if ($status != AZ_OK)
	{
	    return undef;
	}
	# Find the OPF file - there should be only one
	my @members = $zip->membersMatching('.*\.opf');
	if (@members && $members[0])
	{
	    my $opf = $zip->contents($members[0]);
	    my $dom = XML::LibXML->load_xml(string => $opf,
		load_ext_dtd => 0,
		no_network => 1);
	    my @metanodes = $dom->getElementsByLocalName('metadata');
	    foreach my $metanode (@metanodes)
	    {
		if ($metanode->hasChildNodes)
		{
		    my @children = $metanode->childNodes();
		    foreach my $node (@children)
		    {
			parse_one_node(node=>$node,
			    values=>\%values);
		    }
		}
	    }
	}
	$values{is_epub} = 1;
	return \%values;
    }
    return undef;

} # parse_epub_vars

sub parse_one_node {
    my %params = @_;

    my $node = $params{node};
    my $oldvals = $params{values};

    my %newvals = ();
    my $name = $node->localname;
    return undef unless $name;

    my $value = $node->textContent;
    $value =~ s/^\s+//s;
    $value =~ s/\s+$//s;
    $value =~ s/\s+/ /gs;
    if ($name eq 'meta' and $node->hasAttributes)
    {
	my $metaname = '';
	my $metacontent = '';
	my @atts = $node->attributes();
	foreach my $att (@atts)
	{
	    my $n = $att->localname;
	    my $v = $att->value;
	    $v =~ s/^\s+//s;
	    $v =~ s/\s+$//s;
	    if ($n eq 'name')
	    {
		$metaname = $v;
	    }
	    else
	    {
		$metacontent = $v;
	    }
	}
	$newvals{$metaname} = $metacontent;
    }
    elsif ($node->hasAttributes)
    {
	$newvals{$name}->{text} = $value unless !$value;
	my @atts = $node->attributes();
	foreach my $att (@atts)
	{
	    my $n = $att->localname;
	    my $v = $att->value;
	    $v =~ s/^\s+//s;
	    $v =~ s/\s+$//s;
	    $newvals{$name}->{$n} = $v;
	}
    }
    else
    {
	$newvals{$name} = $value;
    }

    # Re-interpret Dublin Core to our own schema
    foreach my $nm (sort keys %newvals)
    {
	my $val = $newvals{$nm};
	if ($nm eq 'creator' and !ref $val)
	{
	    $newvals{author} = $val;
	    $newvals{authorsort} = $val;
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'creator'
		and ((exists $val->{role} and $val->{role} eq 'aut')
		    or !exists $val->{role})
	)
	{
	    $newvals{author} = $val->{text};
	    $newvals{authorsort} = (exists $val->{'file-as'}
		? $val->{'file-as'}
		: $val->{text});
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'date' and ref $val and exists $val->{event})
	{
	    my $event = $val->{event};
	    $newvals{"${event}-date"} = $val->{text};
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'subject')
	{
	    $newvals{category} = $val;
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'source' and $val =~ /^http/)
	{
	    $newvals{elsewhere} = $val;
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'identifier'
		and ref $val
		and exists $val->{scheme}
		and $val->{scheme} =~ /URI/i)
	{
	    $newvals{elsewhere} = $val->{text};
	    delete $newvals{$nm};
	}
	elsif ($nm eq 'title')
	{
	    $newvals{fulltitle} = $val;
	    if ($val =~ /^(?:The |A )(.*)/)
	    {
		$newvals{titlesort} = $1;
	    }
	}
    }

    # Don't want to overwrite existing values
    foreach my $newname (sort keys %newvals)
    {
	my $newval = $newvals{$newname};
	if (!ref $newval)
	{
	    if (!exists $oldvals->{$newname})
	    {
		$oldvals->{$newname} = $newval;
	    }
	    elsif (!ref $oldvals->{$newname}) 
	    {
		my $v = $oldvals->{$newname};
		$oldvals->{$newname} = [$v, $newval];
	    }
	    elsif (ref $oldvals->{$newname} eq 'ARRAY')
	    {
		push @{$oldvals->{$newname}}, $newval;
	    }
	    else
	    {
		$oldvals->{$newname}->{$newval} = $newval;
	    }
	}
	else
	{
	    if (!exists $oldvals->{$newname})
	    {
		$oldvals->{$newname} = $newval;
	    }
	    elsif (ref $oldvals->{$newname} eq 'ARRAY')
	    {
		push @{$oldvals->{$newname}}, $newval;
	    }
	    else
	    {
		my $v = $oldvals->{$newname};
		$oldvals->{$newname} = [$v, $newval];
	    }
	}
    }
} # parse_one_node

1;
