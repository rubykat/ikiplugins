#!/usr/bin/perl
# Ikiwiki getfield plugin.
# Substitute field values in the content of the page.
package IkiWiki::Plugin::getfield;
use strict;
=head1 NAME

IkiWiki::Plugin::getfield - query the values of fields

=head1 VERSION

This describes version B<0.02> of IkiWiki::Plugin::getfield

=cut

our $VERSION = '0.02';

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

=head2 USAGE

One can get the value of a field by using special markup in the page.
This does not use directive markup, in order to make it easier to
use the markup inside other directives.  There are four forms:

=over

=item {{$I<fieldname>}}

This queries the value of I<fieldname> for the source page.

For example:

    [[!meta title="My Long and Complicated Title With Potential For Spelling Mistakes"]]
    # {{$title}}

When the page is processed, this will give you:

    <h1>My Long and Complicated Title With Potential For Spelling Mistakes</h1>

=item {{$I<pagename>#I<fieldname>}}

This queries the value of I<fieldname> for the page I<pagename>.

For example:

On PageFoo:

    [[!meta title="I Am Page Foo"]]

    Stuff about Foo.

On PageBar:

    For more info, see [[{{$PageFoo#title}}|PageFoo]].

When PageBar is displayed:

    <p>For more info, see <a href="PageFoo">I Am Page Foo</a>.</p>

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

=item {{+$I<pagename>#I<fieldname>+}}

This queries the value of I<fieldname> for the page I<pagename>; the
only difference between this and {{$I<pagename>#I<fieldname>}} is
that the full name of I<pagename> is calculated relative to the
destination page rather than the source page.

I can't really think of a reason why this should be needed, but
this format has been added for completeness.

=back

=head2 No Value Found

If no value is found for the given field, then the field name is returned.

For example:

On PageFoo:

    [[!meta title="Foo"]]
    My title is {{$title}}.
    
    My description is {{$description}}.

When PageFoo is displayed:

    <p>My title is Foo.</p>
    
    <p>My description is description.</p>

This is because "description" hasn't been defined for that page.

=head2 More Examples

Listing all the sub-pages of the current page:

    [[!map pages="{{$page}}/*"]]

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
