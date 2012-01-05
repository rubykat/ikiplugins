#!/usr/bin/perl
package IkiWiki::Plugin::pdf_field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::pdf_field - field parser for PDF files

=head1 VERSION

This describes version B<0.20120105> of IkiWiki::Plugin::pdf_field

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
use Image::ExifTool;

my $exifTool;
my %Cache = ();

sub import {
	hook(type => "getsetup", id => "pdf_field", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'pdf_field',
	get_value=>\&get_pdf_value);

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
sub get_pdf_value ($$) {
    my $field_name = shift;
    my $page = shift;

    if (!exists $Cache{$page})
    {
	my $values = parse_pdf_vars(page=>$page);
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
} # get_pdf_value

#-------------------------------------------------------
# Private functions
#-------------------------------------------------------
sub parse_pdf_vars ($$) {
    my %params = @_;
    my $page = $params{page};

    if (!$exifTool)
    {
	$exifTool = new Image::ExifTool;
	$exifTool->Options(Charset => 'UTF8');
    }

    my $file = $pagesources{$page};
    return undef if (!$file);

    my $page_type = pagetype($file);
    if ($file =~ /\.pdf$/i or ($page_type and $page_type eq 'pdf'))
    {
	my %values = ();
	my $srcfile = srcfile($file, 1);
	my $info = $exifTool->ImageInfo($srcfile);
	foreach my $key (sort keys %{$info})
	{
	    parse_value(values=>\%values, key=>$key, info=>$info);
	}

	$values{is_pdf} = 1;
	return \%values;
    }
    return undef;
} # parse_pdf_vars

sub parse_value {
    my %params = @_;

    my $key = $params{key};
    my $values = $params{values};
    my $info = $params{info};

    # Note that when there are multiple instances of a tag
    # we want the latest; therefore always overwrite
    # earlier values.
    my $name = Image::ExifTool::GetTagName($key);
    my $lc_name = $name;
    $lc_name =~ tr/A-Z/a-z/;
    $values->{$lc_name} = $info->{$key};

    # Re-interpret keys to our own schema
    my $val = $values->{$lc_name};
    if ($lc_name eq 'title')
    {
	$values->{fulltitle} = $val;
	if ($val =~ /^(?:The |A )(.*)/)
	{
	    $values->{titlesort} = $1;
	}
    }
    elsif ($lc_name eq 'createdate')
    {
	if ($val =~ /^(\d+):(\d+):(\d+)/)
	{
	    my $year = $1;
	    my $month = $2;
	    my $day = $3;
	    $values->{date} = "${year}-${month}-${day}";
	}
    }

} # parse_value

1;
