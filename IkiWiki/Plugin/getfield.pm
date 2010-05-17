#!/usr/bin/perl
# Ikiwiki getfield plugin.
# Substitute field values in the content of the page.
# See plugin/contrib/getfield for documentation.
package IkiWiki::Plugin::getfield;
use strict;
=head1 NAME

IkiWiki::Plugin::getfield - query the values of fields

=head1 VERSION

This describes version B<0.02> of IkiWiki::Plugin::getfield

=cut

our $VERSION = '0.02';

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "getfield",  call => \&getsetup);
	hook(type => "filter", id => "getfield", call => \&do_filter, last=>1);

	IkiWiki::loadplugin("field");
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub do_filter (@) {
    my %params=@_;
    my $page = $params{page};
    my $destpage = ($params{destpage} ? $params{destpage} : $params{page});

    my $page_file=$pagesources{$page};
    my $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	while ($params{content} =~ /{{\$([-\w\/]+#)?[-\w]+}}/)
	{
	    # substitute {{$var}} variables (source-page)
	    $params{content} =~ s/{{\$([-\w]+)}}/get_field_value($1,$page)/eg;

	    # substitute {{$page#var}} variables (source-page)
	    $params{content} =~ s/{{\$([-\w\/]+)#([-\w]+)}}/get_other_page_field_value($2,$page,$1)/eg;
	}
    }

    $page_file=$pagesources{$destpage};
    $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	while ($params{content} =~ /{{\+\$([-\w\/]+#)?[-\w]+\+}}/)
	{
	    # substitute {{+$var+}} variables (dest-page)
	    $params{content} =~ s/{{\+\$([-\w]+)\+}}/get_field_value($1,$destpage)/eg;
	    # substitute {{+$page#var+}} variables (source-page)
	    $params{content} =~ s/{{\+\$([-\w\/]+)#([-\w]+)\+}}/get_other_page_field_value($2,$destpage,$1)/eg;
	}
    }

    return $params{content};
} # do_filter

#---------------------------------------------------------------
# Private functions
# --------------------------------
sub get_other_page_field_value ($$$) {
    my $field = shift;
    my $page = shift;
    my $other_page = shift;

    my $use_page = bestlink($page, $other_page);
    my $val = get_field_value($field, $use_page);
    if ($val eq $field)
    {
	return "${other_page}#$field";
    }
    return $val;

} # get_other_page_field_value

sub get_field_value ($$) {
    my $field = shift;
    my $page = shift;

    my $value = IkiWiki::Plugin::field::field_get_value($field,$page);
    return $value if defined $value;

    # if there is no value, return the field name.
    return $field;
} # get_field_value

1;
