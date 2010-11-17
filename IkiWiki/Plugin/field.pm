#!/usr/bin/perl
# Ikiwiki field plugin.
# See doc/plugin/contrib/field.mdwn for documentation.
package IkiWiki::Plugin::field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::field - front-end for per-page record fields.

=head1 VERSION

This describes version B<1.20101101> of IkiWiki::Plugin::field

=cut

our $VERSION = '1.20101115';

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2010 Kathryn Andersen

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

sub field_get_value ($$);

sub import {
	hook(type => "getsetup", id => "field",  call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "scan", id => "field", call => \&scan, last=>1);
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
		field_tags => {
			type => "hash",
			example => "field_tags => {BookAuthor => '/books/authors'}",
			description => "fields flagged as tag-fields",
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

sub scan (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};

    # scan for tag fields
    if ($config{field_tags})
    {
	foreach my $field (keys %{$config{field_tags}})
	{
	    my @values = field_get_value($field, $page);
	    if (@values)
	    {
		foreach my $tag (@values)
		{
		    if ($tag)
		    {
			my $link = $config{field_tags}{$field} . '/'
			. titlepage($tag);
			add_link($page, $link, lc($field));
		    }
		}
	    }
	}
    }
} # scan

sub pagetemplate (@) {
    my %params=@_;
    my $page=$params{page};
    my $template=$params{template};

    field_set_template_values($template, $page);
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

    my $id = $param{id};
    $Fields{$id} = \%param;

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
    add_lookup_order($id, $when);
    return 1;
} # field_register

sub field_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    # This will return the first value it finds
    # where the value returned is not undefined.
    # This will return an array of values if wantarray is true.

    # The reason why it checks every registered plugin rather than have
    # plugins declare which fields they know about, is that it is quite
    # possible that a plugin doesn't know, ahead of time, what fields
    # will be available; for example, a YAML format plugin would return
    # any field that happens to be defined in a YAML page file, which
    # could be anything!
 
    # check the cache first
    my $lc_field_name = lc($field_name);
    if (wantarray)
    {
	if (exists $Cache{$page}{$lc_field_name}{array}
	    and defined $Cache{$page}{$lc_field_name}{array})
	{
	    return @{$Cache{$page}{$lc_field_name}{array}};
	}
    }
    else
    {
	if (exists $Cache{$page}{$lc_field_name}{scalar}
	    and defined $Cache{$page}{$lc_field_name}{scalar})
	{
	    return $Cache{$page}{$lc_field_name}{scalar};
	}
    }

    if (!@FieldsLookupOrder)
    {
	build_fields_lookup_order();
    }

    # Get either the scalar or the array value depending
    # on what is requested - don't get both because it wastes time.
    if (wantarray)
    {
	my @array_value = undef;
	foreach my $id (@FieldsLookupOrder)
	{
	    # get the data from the pagestate hash if it's there
	    if (exists $pagestate{$page}{$id}{$field_name}
		and defined $pagestate{$page}{$id}{$field_name})
	    {
		@array_value = (ref $pagestate{$page}{$id}{$field_name}
				? @{$pagestate{$page}{$id}{$field_name}}
				: ($pagestate{$page}{$id}{$field_name}));
	    }
	    elsif (exists $pagestate{$page}{$id}{$lc_field_name}
		   and defined $pagestate{$page}{$id}{$lc_field_name})
	    {
		@array_value = (ref $pagestate{$page}{$id}{$lc_field_name}
				? @{$pagestate{$page}{$id}{$lc_field_name}}
				: ($pagestate{$page}{$id}{$lc_field_name}));
	    }
	    elsif (exists $Fields{$id}{call})
	    {
		@array_value = $Fields{$id}{call}->($field_name, $page);
	    }
	    if (@array_value and $array_value[0])
	    {
		last;
	    }
	}
	if (!@array_value)
	{
	    @array_value = field_calculated_values($field_name, $page);
	}
	# cache the value
	$Cache{$page}{$lc_field_name}{array} = \@array_value;
	return @array_value;
    }
    else # scalar
    {
	my $value = undef;
	foreach my $id (@FieldsLookupOrder)
	{
	    # get the data from the pagestate hash if it's there
	    # but only if it's already a scalar
	    if (exists $pagestate{$page}{$id}{$field_name}
		and !ref $pagestate{$page}{$id}{$field_name})
	    {
		$value = $pagestate{$page}{$id}{$field_name};
	    }
	    elsif (exists $pagestate{$page}{$id}{$lc_field_name}
		   and !ref $pagestate{$page}{$id}{$lc_field_name})
	    {
		$value = $pagestate{$page}{$id}{$lc_field_name};
	    }
	    elsif (exists $Fields{$id}{call})
	    {
		$value = $Fields{$id}{call}->($field_name, $page);
	    }
	    if (defined $value)
	    {
		last;
	    }
	}
	if (!defined $value)
	{
	    $value = field_calculated_values($field_name, $page);
	}
	# cache the value
	$Cache{$page}{$lc_field_name}{scalar} = $value;
	return $value;
    }

    return undef;
} # field_get_value

# set the values for the given HTML::Template template
sub field_set_template_values ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    my $get_value_fn = (exists $params{value_fn}
			? $params{value_fn}
			: \&field_get_value);

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
	# Don't redefine if the field already has a value set.
	next if ($template->param($field));

	my $type = $template->query(name => $field);
	if ($type eq 'LOOP' and $field =~ /_LOOP$/oi)
	{
	    # Loop fields want arrays.
	    # Figure out what field names to look for:
	    # * names are from the enclosed loop fields
	    my @loop_fields = $template->query(loop => $field);

	    my @loop_vals = ();
	    my %loop_field_arrays = ();
	    foreach my $fn (@loop_fields)
	    {
		if ($fn !~ /^__/o) # not a special loop variable
		{
		    my @ival_array = $get_value_fn->($fn, $page);
		    if (@ival_array)
		    {
			$loop_field_arrays{$fn} = \@ival_array;
		    }
		}
	    }
	    foreach my $fn (sort keys %loop_field_arrays)
	    {
		my $i = 0;
		foreach my $v (@{$loop_field_arrays{$fn}})
		{
		    if (!defined $loop_vals[$i])
		    {
			$loop_vals[$i] = {};
		    }
		    $loop_vals[$i]{$fn} = $v;
		    $i++;
		}
	    }
	    $template->param($field => \@loop_vals);
	}
	else # not a loop field
	{
	    my $value = $get_value_fn->($field, $page);
	    if (defined $value)
	    {
		$template->param($field => $value);
	    }
	}
    }
} # field_set_template_values

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
    if ($when =~ /^[A-Z][A-Z]$/o)
    {
	$Fields{$id}{seq} = $when;
    }
    else
    {
	my $cmp = '=';
	my $seq_field = $when;
	if ($when =~ /^([<>])(.+)$/o)
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

# standard values deduced from other values
sub field_calculated_values {
    my $field_name = shift;
    my $page = shift;

    my $value = undef;

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
    # the page above this page; aka the current directory
    elsif ($field_name eq 'parent_page')
    {
	if ($page =~ m{^(.*)/[-\.\w]+$}o)
	{
	    $value = $1;
	}
    }
    elsif ($field_name eq 'basename')
    {
	$value = IkiWiki::basename($page);
    }
    elsif ($config{field_allow_config}
	   and $field_name =~ /^config-(.*)$/oi)
    {
	my $cfield = $1;
	if (exists $config{$cfield})
	{
	    $value = $config{$cfield};
	}
    }
    elsif ($field_name =~ /^(.*)-tagpage$/o)
    {
	my @array_value = undef;
	my $real_fn = $1;
	if (exists $config{field_tags}{$real_fn}
	    and defined $config{field_tags}{$real_fn})
	{
	    my @values = field_get_value($real_fn, $page);
	    if (@values)
	    {
		foreach my $tag (@values)
		{
		    if ($tag)
		    {
			my $link = $config{field_tags}{$real_fn} . '/' . $tag;
			push @array_value, $link;
		    }
		}
		if (wantarray)
		{
		    return @array_value;
		}
		else
		{
		    $value = join(",", @array_value) if $array_value[0];
		}
	    }
	}
    }
    return (wantarray ? ($value) : $value);
} # field_calculated_values

# match field funcs
# page-to-check, wanted
sub match_a_field ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.*)$/o)
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
} # match_a_field

# check against individual items of a field
# (treat the field as an array)
# page-to-check, wanted
sub match_a_field_item ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.*)$/o)
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

    my @val_array = IkiWiki::Plugin::field::field_get_value($field_name, $page);

    if (@val_array)
    {
	foreach my $val (@val_array)
	{
	    if (defined $val) {
		if ($val=~/^$re$/i) {
		    return IkiWiki::SuccessReason->new("$re matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
		}
	    }
	}
	# not found
	return IkiWiki::FailReason->new("$re does not match $field_name of $page", "" => 1);
    }
    else {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }
} # match_a_field_item

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_field ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::match_a_field($page, $wanted);
} # match_field

sub match_destfield ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    return IkiWiki::Plugin::field::match_a_field($params{destpage}, $wanted);
} # match_destfield

sub match_field_item ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::match_a_field_item($page, $wanted);
} # match_field

sub match_destfield_item ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    return IkiWiki::Plugin::field::match_a_field_item($params{destpage}, $wanted);
} # match_destfield

sub match_field_tagged ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.*)$/o)
    {
	$field_name = $1;
	$glob = $2;
    }
    else
    {
	return IkiWiki::FailReason->new("cannot match field");
    }
    return match_link($page, $glob, linktype => lc($field_name), @_);
}

sub match_destfield_tagged ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    return IkiWiki::FailReason->new("cannot match destpage") unless exists $params{destpage};

    # Match the field on the destination page, not the source page
    return IkiWiki::Plugin::field::match_field_tagged($params{destpage}, $wanted);
}

# ===============================================
# SortSpec functions
# ---------------------------
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

sub cmp_field_natural {
    my $field = shift;
    error(gettext("sort=field requires a parameter")) unless defined $field;

    eval q{use Sort::Naturally};
    error $@ if $@;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    return Sort::Naturally::ncmp($left, $right);
}

1;
