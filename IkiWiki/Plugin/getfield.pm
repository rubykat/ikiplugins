#!/usr/bin/perl
# Ikiwiki getfield plugin.
# Substitute field values in the content of the page.
package IkiWiki::Plugin::getfield;
use strict;
=head1 NAME

IkiWiki::Plugin::getfield - query the values of fields

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::getfield

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    # activate the plugin
    add_plugins => [qw{goodstuff getfield ....}],

=head1 DESCRIPTION

This plugin provides a way of querying the meta-data (data fields) of a page
inside the page content (rather than inside a template) This provides a way to
use per-page structured data, where each page is treated like a record, and the
structured data are fields in that record.  This can include the meta-data for
that page, such as the page title.

This plugin is meant to be used in conjunction with the B<field> plugin.

=head2 USEAGE

One can get the value of a field by using special markup in the page.
This does not use directive markup, in order to make it easier to
use the markup inside other directives.  There are two forms:

=over

=item {{$I<fieldname>}}

This queries the value of I<fieldname> for the source page.

For example:

    [[!meta title="My Long and Complicated Title With Potential For Spelling Mistakes"]]
    # {{$title}}

When the page is processed, this will give you:

    <h1>My Long and Complicated Title With Potential For Spelling Mistakes</h1>

=item {{+$I<fieldname>+}}

This queries the value of I<fieldname> for the destination page; that is,
the value when this page is included inside another page.

For example:

On PageA:

    [[!meta title="I Am Page A"]]
    # {{+$title+}}

    Stuff about A.

On PageB:

    [[!meta title="I Am Page B"]]
    [[!inline pagespec="PageA"]]

When PageA is displayed:

    <h1>I Am Page A</h1>
    <p>Stuff about A.</p>

When PageB is displayed:

    <h1>I Am Page B</h1>
    <p>Stuff about A.</p>

=back

=head2 More Examples

Listing all the sub-pages of the current page:

    [[!map pages="{{$page}}/*"]]

=head2 LIMITATIONS

One cannot query the values of fields on pages other than the current
page or the destination page.

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
	# substitute {{$var}} variables (source-page)
	$params{content} =~ s/{{\$([-\w]+)}}/get_field_value($1,$page)/eg;
    }

    $page_file=$pagesources{$destpage};
    $page_type=pagetype($page_file);
    if (defined $page_type)
    {
	# substitute {{+$var+}} variables (dest-page)
	$params{content} =~ s/{{\+\$([-\w]+)\+}}/get_field_value($1,$destpage)/eg;
    }

    return $params{content};
} # do_filter

#---------------------------------------------------------------
# Private functions
# --------------------------------
sub get_field_value ($$) {
    my $field = shift;
    my $page = shift;

    my $value = IkiWiki::Plugin::field::field_get_value($field,$page);
    return $value if defined $value;

    # if there is no value, return the unchanged field name.
    return "{\$$field}";
} # get_field_value

1;
