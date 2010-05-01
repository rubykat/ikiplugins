#!/usr/bin/perl
# Ikiwiki field plugin.
package IkiWiki::Plugin::field;
use warnings;
use strict;
use YAML::Any;
=head1 NAME

IkiWiki::Plugin::field - front-end for per-page record fields.

=head1 VERSION

This describes version B<0.03> of IkiWiki::Plugin::field

=cut

our $VERSION = '0.03';

=head1 SYNOPSIS

    # activate the plugin
    add_plugins => [qw{goodstuff field ....}],

    # simple registration
    field_register => [qw{meta}],

    # allow the config to be queried as a field
    field_allow_config => 1,

=head1 DESCRIPTION

This plugin is meant to be used in conjunction with other plugins
in order to provide a uniform interface to access per-page structured
data, where each page is treated like a record, and the structured data
are fields in that record.  This can include the meta-data for that page,
such as the page title.

Plugins can register a function which will return the value of a "field" for
a given page.  This can be used in three ways:

=over

=item *

In page templates; all registered fields will be passed to the page template
in the "pagetemplate" processing.

=item *

In PageSpecs; the "field" function can be used to match the value of a field
in a page.

=item *

By other plugins, using the field_get_value function, to get the value of a field
for a page, and do with it what they will.

=back

=head1 OPTIONS

The following options can be set in the ikiwiki setup file.

=over

=item field_allow_config

    field_allow_config => 1,

Allow the $config hash to be queried like any other field; the 
keys of the config hash are the field names.

=item field_register

    field_register => {
	meta => 'last'
	foo => 'DD'
    },

A hash of plugin-IDs to register.  The keys of the hash are the names of the
plugins, and the values of the hash give the order of lookup of the field
values.  The order can be 'first', 'last', 'middle', or an explicit order
sequence between 'AA' and 'ZZ'.

This assumes that the plugins in question store data in the %pagestatus hash
using the ID of that plugin, and thus the field values are looked for there.

This is the simplest form of registration, but the advantage is that it
doesn't require the plugin to be modified in order for it to be
registered with the "field" plugin.

=back

=head1 PageSpec

The "field" PageSpec function can be used to match the value of a field for a page.

field(I<name> I<glob>)

For example:

field(bar Foo*) will match if the "bar" field in the source page starts with "Foo".

destfield(I<name> I<glob>)

is the same, except that it tests the destination page (that is, in cases
when the source page is being included in another page).

=head1 SortSpec

The "field" SortSpec function can be used to sort a page depending on the value of a field for that page.  This is used for directives that take sort parameters, such as B<inline> or B<report>.

field(I<name>)

For example:

sort="field(bar)" will sort by the value og the "bar" field.

=head1 FUNCTIONS

=over

=item field_register

field_register(id=>$id);

Register a plugin as having field data.  The above form is the simplest, where
the field value is looked up in the %pagestatus hash under the plugin-id.

Additional Options:

=over

=item call=>&myfunc

A reference to a function to call rather than just looking up the value in the
%pagestatus hash.  It takes two arguments: the name of the field, and the name
of the page.  It is expected to return the value of that field, or undef if
there is no field by that name.

    sub myfunc ($$) {
	my $field = shift;
	my $page = shift;

	...

	return $value;
    }

=item first=>1

Set this to be called first in the sequence of calls looking for values.  Since
the first found value is the one which is returned, ordering is significant.
This is equivalent to "order=>'first'".

=item last=>1

Set this to be called last in the sequence of calls looking for values.  Since
the first found value is the one which is returned, ordering is significant.
This is equivalent to "order=>'last'".

=item order=>$order

Set the explicit ordering in the sequence of calls looking for values.  Since
the first found value is the one which is returned, ordering is significant.

The values allowed for this are "first", "last", "middle", or a two-character
ordering-sequence between 'AA' and 'ZZ'.

=back

=item field_get_value($field, $page)

Returns the value of the field for that page, or undef if none is found.

=back

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

my %Fields = (
    _first => {
	id => '_first',
	seq => 'BB',
    },
    _last => {
	id => '_last',
	seq => 'YY',
    },
    _middle => {
	id => '_middle',
	seq => 'MM',
    },
);
my @FieldsLookupOrder = ();

my %Cache = ();

sub import {
	hook(type => "getsetup", id => "field",  call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "pagetemplate", id => "field", call => \&pagetemplate);
}

# ===============================================
# Hooks
# ---------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		field_register => {
			type => "hash",
			example => "field_register => {meta => 'last'}",
			description => "simple registration of fields by plugin",
			safe => 0,
			rebuild => undef,
		},
		field_allow_config => {
			type => "boolean",
			example => "field_allow_config => 1",
			description => "allow config settings to be queried",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    # use the simple by-plugin pagestatus method for
    # those plugins registered with the field_register config option.
    if (defined $config{field_register})
    {
	if (ref $config{field_register} eq 'ARRAY')
	{
	    foreach my $id (@{$config{field_register}})
	    {
		field_register(id=>$id);
	    }
	}
	elsif (ref $config{field_register} eq 'HASH')
	{
	    foreach my $id (keys %{$config{field_register}})
	    {
		field_register(id=>$id, order=>$config{field_register}->{$id});
	    }
	}
	else
	{
	    field_register(id=>$config{field_register});
	}
    }
    if (!defined $config{field_allow_config})
    {
	$config{field_allow_config} = 0;
    }
} # checkconfig

sub pagetemplate (@) {
    my %params=@_;
    my $page=$params{page};
    my $template=$params{template};

    # Find the parameter names in this template
    # and see if you can find their values.

    # The reason we check the template for field names is because we
    # don't know what fields the registered plugins provide; and this is
    # reasonable because for some plugins (e.g. a YAML data plugin) they
    # have no way of knowing, ahead of time, what fields they might be
    # able to provide.

    my @parameter_names = $template->param();
    foreach my $field (@parameter_names)
    {
	my $value = field_get_value($field, $page);
	if (defined $value)
	{
	    $template->param($field => $value);
	}
    }
} # pagetemplate

# ===============================================
# Field interface
# ---------------------------

sub field_register (%) {
    my %param=@_;
    if (!exists $param{id})
    {
	error 'field_register requires id parameter';
	return 0;
    }
    if (exists $param{call} and !ref $param{call})
    {
	error 'field_register call parameter must be function';
	return 0;
    }

    $Fields{$param{id}} = \%param;
    if (!exists $param{call})
    {
	# closure to get the data from the pagestate hash
	$Fields{$param{id}}->{call} = sub {
	    my $field_name = shift;
	    my $page = shift;
	    if (exists $pagestate{$page}{$param{id}}{$field_name})
	    {
		return $pagestate{$page}{$param{id}}{$field_name};
	    }
	    elsif (exists $pagestate{$page}{$param{id}}{lc($field_name)})
	    {
		return $pagestate{$page}{$param{id}}{lc($field_name)};
	    }
	    return undef;
	};
    }
    # add this to the ordering hash
    # first, last, order; by default, middle
    my $when = ($param{first}
		? '_first'
		: ($param{last}
		   ? '_last'
		   : ($param{order}
		      ? ($param{order} eq 'first'
			 ? '_first'
			 : ($param{order} eq 'last'
			    ? '_last'
			    : ($param{order} eq 'middle'
			       ? '_middle'
			       : $param{order}
			      )
			   )
			)
		      : '_middle'
		     )
		  ));
    add_lookup_order($param{id}, $when);
    return 1;
} # field_register

sub field_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    # This will return the first value it finds
    # where the value returned is not undefined.

    # The reason why it checks every registered plugin rather than have
    # plugins declare which fields they know about, is that it is quite
    # possible that a plugin doesn't know, ahead of time, what fields
    # will be available; for example, a YAML format plugin would return
    # any field that happens to be defined in a YAML page file, which
    # could be anything!
 
    my $value = undef;

    # check the cache first
    if (exists $Cache{$page}{$field_name}
	and defined $Cache{$page}{$field_name})
    {
	return $Cache{$page}{$field_name};
    }

    if (!@FieldsLookupOrder)
    {
	build_fields_lookup_order();
    }
    foreach my $id (@FieldsLookupOrder)
    {
	$value = $Fields{$id}{call}->($field_name, $page);
	if (defined $value)
	{
	    last;
	}
    }

    # extra definitions
    if (!defined $value)
    {
	# Exception for titles
	# If the title hasn't been found, construct it
	if ($field_name eq 'title')
	{
	    $value = pagetitle(IkiWiki::basename($page));
	}
	# and set "page" if desired
	elsif ($field_name eq 'page')
	{
	    $value = $page;
	}
	elsif ($field_name eq 'basename')
	{
	    $value = IkiWiki::basename($page);
	}
	elsif ($field_name =~ /^config-(.*)$/i)
	{
	    my $cfield = $1;
	    if (exists $config{$cfield})
	    {
		$value = $config{$cfield};
	    }
	}
    }
    if (defined $value)
    {
	# cache the value
	$Cache{$page}{$field_name} = $value;
    }
    return $value;
} # field_get_value

# ===============================================
# Private Functions
# ---------------------------

# Calculate the lookup order
# <module, >module, AZ
# This is crabbed from the PmWiki Markup function
sub add_lookup_order  {
    my $id = shift;
    my $when = shift;

    # may have given an explicit ordering
    if ($when =~ /^[A-Z][A-Z]$/)
    {
	$Fields{$id}{seq} = $when;
    }
    else
    {
	my $cmp = '=';
	my $seq_field = $when;
	if ($when =~ /^([<>])(.+)$/)
	{
	    $cmp = $1;
	    $seq_field = $2;
	}
	$Fields{$seq_field}{dep}{$id} = $cmp;
	if (exists $Fields{$seq_field}{seq}
	    and defined $Fields{$seq_field}{seq})
	{
	    $Fields{$id}{seq} = $Fields{$seq_field}{seq} . $cmp;
	}
    }
    if ($Fields{$id}{seq})
    {
	foreach my $i (keys %{$Fields{$id}{dep}})
	{
	    my $m = $Fields{$id}{dep}{$i};
	    add_lookup_order($i, "$m$id");
	}
	delete $Fields{$id}{dep};
    }
}

sub build_fields_lookup_order {

    # remove the _first, _last and _middle dummy fields
    # because we don't need them anymore
    delete $Fields{_first};
    delete $Fields{_last};
    delete $Fields{_middle};
    my %lookup_spec = ();
    # Make a hash of the lookup sequences
    foreach my $id (sort keys %Fields)
    {
	my $seq = ($Fields{$id}{seq}
		   ? $Fields{$id}{seq}
		   : 'MM');
	if (!exists $lookup_spec{$seq})
	{
	    $lookup_spec{$seq} = {};
	}
	$lookup_spec{$seq}{$id} = 1;
    }

    # get the field-lookup order by (a) sorting by lookup_spec
    # and (b) sorting by field-name for the fields that registered
    # the same field-lookup order
    foreach my $ord (sort keys %lookup_spec)
    {
	push @FieldsLookupOrder, sort keys %{$lookup_spec{$ord}};
    }
} # build_fields_lookup_order

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_field ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.*)$/)
    {
	$field_name = $1;
	$glob = $2;
    }
    else
    {
	return IkiWiki::FailReason->new("cannot match field");
    }

    # turn glob into a safe regexp
    my $re=IkiWiki::glob2re($glob);

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);

    if (defined $val) {
	if ($val=~/^$re$/i) {
	    return IkiWiki::SuccessReason->new("$re matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
	}
	else {
	    return IkiWiki::FailReason->new("$re does not match $field_name of $page", "" => 1);
	}
    }
    else {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }
} # match_field

sub match_destfield ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.*)$/)
    {
	$field_name = $1;
	$glob = $2;
    }
    else
    {
	return IkiWiki::FailReason->new("cannot match field");
    }

    # turn glob into a safe regexp
    my $re=IkiWiki::glob2re($glob);

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $params{destpage});

    if (defined $val) {
	if ($val=~/^$re$/i) {
	    return IkiWiki::SuccessReason->new("$re matches $field_name of $params{destpage}", $params{destpage} => $IkiWiki::DEPEND_CONTENT, "" => 1);
	}
	else {
	    return IkiWiki::FailReason->new("$re does not match $field_name of $params{destpage}", "" => 1);
	}
    }
    else {
	return IkiWiki::FailReason->new("$params{destpage} does not have a $field_name", "" => 1);
    }
} # match_destfield

package IkiWiki::SortSpec;

sub cmp_field {
    my $field = shift;
    error(gettext("sort=field requires a parameter")) unless defined $field;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    return $left cmp $right;
}

1;
