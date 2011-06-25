#!/usr/bin/perl
# Ikiwiki field plugin.
package IkiWiki::Plugin::field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::field - middle-end for per-page record fields.

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::field

=cut

our $VERSION = '1.20110610';

=head1 DESCRIPTION

Used by other plugins as an interface; treats each page as
a record which can have multiple fields.

See doc/plugin/contrib/field.mdwn for documentation.

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

my $FieldO;

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

my %FieldCalcs = ();

sub field_get_value ($$;@);

sub import {
	hook(type => "getsetup", id => "field",  call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "preprocess", id => "field", call => \&preprocess, scan=>1);
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

    $FieldO = IkiWiki::Plugin::field::Source->new();

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
    # also register the "field" directive
    field_register(id=>'field_directive');

    if (!defined $config{field_allow_config})
    {
	$config{field_allow_config} = 0;
    }
} # checkconfig

sub preprocess (@) {
    my %params= @_;

    # add the content of the field directive to the fields
    if (!defined wantarray) # scanning
    {
	my $page_type = pagetype($pagesources{$params{page}});
	# perform htmlizing on content on HTML pages
	$page_type = $config{default_pageext} if $page_type eq 'html';

	foreach my $key (keys %params)
	{
	    if ($key =~ /^(page|destpage|preview|_raw)$/) # skip non-fieldname things
	    {
		next;
	    }
	    my $value = $params{$key};
	    if ($value and !$params{_raw})
	    {
		# HTMLize the text
		$value = IkiWiki::htmlize($params{page},
					  $params{destpage},
					  $page_type,
					  $value) unless (!$page_type);

		# Preprocess the text to expand any preprocessor directives
		# embedded inside it.
		# First in scan mode, then in real mode
		my $fake_value = IkiWiki::preprocess
		    ($params{page},
		     $params{destpage}, 
		     IkiWiki::filter($params{page},
				     $params{destpage},
				     $value)
		    );
		($value) = IkiWiki::preprocess
		    ($params{page},
		     $params{destpage}, 
		     IkiWiki::filter($params{page},
				     $params{destpage},
				     $value)
		    );
	    }
	    $pagestate{$params{page}}{field_directive}{$key} = $value;
	}
    }
    return '';
}

sub scan (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};

    remember_values(%params);
    scan_for_tags(%params);
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
    if (exists $param{all_values} and !ref $param{all_values})
    {
	error 'field_register all_values parameter must be function';
	return 0;
    }
    if (exists $param{call} and !exists $param{all_values})
    {
	error 'field_register "call" is obsolete, use "all_values"';
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

sub field_register_calculation (%) {
    my %param=@_;

    foreach my $requires (qw(id call))
    {
	if (!exists $param{$requires})
	{
	    error sprintf("%s requires %s parameter",
		'field_register_calculation', $requires);
	    return 0;
	}
    }
    if (exists $param{call} and !ref $param{call})
    {
	error 'field_register_calculation call parameter must be function';
	return 0;
    }

    my $id = $param{id};
    $FieldCalcs{$id} = \%param;

} # field_register_calculation

sub field_get_value ($$;@) {
    my $field_name = shift;
    my $page = shift;
    my %params = @_;

    # This expects all values to have been remembered in the scan pass.
    # Calculations on fields are given in dot notation.
    # The actual field name must be the first part.
    my @actions = split(/\./, lc($field_name));

    my $pagesource = $pagesources{$page};
    return undef unless $pagesource;
    my $page_type = pagetype($pagesource);

    my $lc_field_name = shift @actions;

    if (exists $params{$lc_field_name})
    {
	my $value = $params{$lc_field_name};
	if (@actions)
	{
	    $value = apply_calculations(value=>$value,
		page=>$page,
		field_name=>$lc_field_name,
		actions=>\@actions);
	}
	return $value;
    }
    else
    {
	my $value = $FieldO->get_value($page, $lc_field_name);
	if ($value and @actions)
	{
	    $value = apply_calculations(value=>$value,
		page=>$page,
		field_name=>$lc_field_name,
		actions=>\@actions);
	}
	return $value;
    }
    return undef;
} # field_get_value

sub field_set_template_values ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    my $ttype = ref $template;

    return field_set_html_template($template, $page, %params);
} # field_set_template_values


# ===============================================
# Private Functions
# ---------------------------

# set the values for the given HTML::Template template
sub field_set_html_template ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    my %vals = $FieldO->get_values($page);
    if (%vals)
    {
	my @parameter_names = $template->param();
	foreach my $field (@parameter_names)
	{
	    # Don't redefine if the field already has a value set.
	    next if ($template->param($field));
	    my $value = (
		(exists $params{$field} and defined $params{$field})
		? $params{$field}
		: ((exists $vals{$field} and defined $vals{$field})
		    ? $vals{$field}
		    : undef
		)
	    );
	    if (defined $value)
	    {
		$template->param($field => $value);
	    }
	}
    }

} # field_set_html_template

# set the values for the given HTML::Template::Pro template
sub field_set_html_template_pro ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    # Note that HTML::Template::Pro cannot query the template
    # so we don't know what values are required for this template
    # so we have to give them ALL
    my %values = $FieldO->get_values($page);
    $template->param(%values);
    $template->param(%params);

    # Note that HTML::Template::Pro has expressions and functions, however.

} # field_set_html_template_pro

sub scan_for_tags (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};

    # scan for tag fields - the field values should be set now
    if ($config{field_tags})
    {
	foreach my $field (keys %{$config{field_tags}})
	{
	    my $lc_field = lc($field);
	    my $loop_val = field_get_value("${lc_field}_loop", $page);
	    if ($loop_val)
	    {
		my @loop = @{$loop_val};
		for (my $i = 0; $i < @loop; $i++)
		{
		    my $tag = $loop[$i]->{$lc_field};
		    my $link = $config{field_tags}{$field} . '/'
		    . titlepage($tag);
		    add_link($page, $link, $lc_field);
		}
	    }
	}
    }
} # scan_for_tags

sub remember_values (@) {
    my %params=@_;
    my $page=$params{page};
    my $content=$params{content};

    # get all the values for this page

    if (!@FieldsLookupOrder)
    {
	build_fields_lookup_order();
    }

    my $pagesource = $pagesources{$page};
    return undef unless $pagesource;
    my $page_type = pagetype($pagesource);

    # These are standard values such as parent_page etc.
    field_add_standard_values($page, $page_type);

    my %values = $FieldO->get_values($page);
    foreach my $id (@FieldsLookupOrder)
    {
	my %vals = ();
	if (exists $Fields{$id}{all_values} and exists $pagestate{$page}{$id})
	{
	    # get both sets of values
	    my $tvals = $Fields{$id}{all_values}->(%params);
	    %vals = %{$tvals} if defined $tvals;
	    foreach my $k (keys %{$pagestate{$page}{$id}})
	    {
		$vals{$k} = $pagestate{$page}{$id}{$k};
	    }
	}
	elsif (exists $pagestate{$page}{$id})
	{
	    %vals = %{$pagestate{$page}{$id}};
	}
	elsif (exists $Fields{$id}{all_values})
	{
	    my $tvals = $Fields{$id}{all_values}->(%params);
	    %vals = %{$tvals} if defined $tvals;
	}
	# Already-set values have priority
	# Remember both scalar and loop values
	# Keys are remembered in lower-case
	foreach my $key (sort keys %vals)
	{
	    my $lc_key = lc($key);
	    if (!exists $values{$lc_key})
	    {
		field_format_values(
		    values => \%values,
		    field=>$lc_key,
		    value=> $vals{$key},
		    page_type=>$page_type,
		    page=>$page);
	    }
	}

	# Do this here so that later plugins can use the values.
	# This is so that one can have values derived from other values.
	$FieldO->set_values($page, %values);

    } # for all registered field plugins

    field_add_calculated_values($page, $page_type);

} # remember_values

sub apply_calculations {
    my %params=@_;

    my $val = $params{value};
    my @actions = @{$params{actions}};

    foreach my $act (@actions)
    {
	if ($act ne 'array')
	{
	    if (exists $FieldCalcs{$act}{call})
	    {
		$val = $FieldCalcs{$act}{call}->(%params,
		    id=>$act,
		    value=>$val);
	    }
	}
    }
    return $val;
} # apply_calculations

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

# Standard values that are always set
# Expects the values for the page NOT to have been figured yet.
sub field_add_standard_values {
    my $page = shift;
    my $page_type = shift;

    my %values = ();
    my @fields = (qw(page parent_page basename));
    foreach my $key (@fields)
    {
	if (!$values{$key})
	{
	    my $val = field_calculated_values($key, $page);
	    field_format_values(values=>\%values,
	    field=>$key,
	    value=>$val,
	    page_type=>$page_type,
	    page=>$page);
	}
    }
    # config - just remember the scalars
    if ($config{field_allow_config})
    {
	foreach my $key (keys %config)
	{
	    if ($key =~ /^_/) # private
	    {
		next;
	    }
	    my $lc_key = lc($key);
	    if (!ref $config{$key})
	    {
		$values{"config-${lc_key}"} = $config{$key};
	    }
	}
    }
    $FieldO->set_values($page, %values);
} # field_add_standard_values

# standard values deduced from other values
# expects the values for the page to be set now
sub field_add_calculated_values {
    my $page = shift;
    my $page_type = shift;

    my %values = $FieldO->get_values($page);
    my @fields = (qw(title titlecaps pagetitle));
    foreach my $key (@fields)
    {
	if (!$values{$key})
	{
	    my $val = field_calculated_values($key, $page);
	    field_format_values(values=>\%values,
	    field=>$key,
	    value=>$val,
	    page_type=>$page_type,
	    page=>$page);
	}
    }
    # tagpages
    foreach my $key (keys %{$config{field_tags}})
    {
	my $lc_key = lc($key);
	# Go through the "_loop" variable
	# to ensure that arrays are treated properly.
	if (exists $values{"${lc_key}_loop"})
	{
	    my @loop = ();
	    my @orig_loop = @{$values{"${lc_key}_loop"}};
	    for (my $i = 0; $i < @orig_loop; $i++)
	    {
		my $tag = $orig_loop[$i]->{$lc_key};
		my $link = $config{field_tags}{$key} . '/' . titlepage($tag);
		$orig_loop[$i]->{"${lc_key}-tagpage"} = $link;
		push @loop, {$lc_key => $link};
	    }
	    $values{"${lc_key}-tagpage"} = join(' ', @loop);
	    $values{"${lc_key}-tagpage_loop"} = \@loop;
	    $values{"${lc_key}_loop"} = \@orig_loop;
	}
    }
    $FieldO->set_values($page, %values);
} # field_add_calculated_values

# Add values in additional formats
# For example, _loop and _html
sub field_format_values {
    my %params = @_;

    my $values = $params{values};
    my $field = $params{field};
    my $value = $params{value};
    my $page_type = $params{page_type};
    my $page = $params{page};

    if (ref $value eq 'ARRAY')
    {
	$values->{${field}} = join(' ', @{$value});
	$values->{"${field}_loop"} = [];
	foreach my $v (@{$value})
	{
	    push @{$values->{"${field}_loop"}}, {$field => $v};
	}
	# When HTML-izing an array, make it a list
	if ($page_type)
	{
	    $values->{"${field}_html"} = IkiWiki::htmlize($page, $page,
		$page_type,
		"\n\n* " . join("\n* ", @{$value}) . "\n");
	}
    }
    elsif (!ref $value)
    {
	$values->{$field} = $value;
	if (defined $value and $value)
	{
	    $values->{"${field}_loop"} = [{$field => $value}];
	    if ($page_type)
	    {
		$values->{"${field}_html"} =
		IkiWiki::htmlize($page, $page, $page_type, $value);
	    }
	}
    }
    return $values;
} # field_format_values

# standard values deduced from other values
sub field_calculated_values {
    my $field_name = shift;
    my $page = shift;

    return undef unless defined $page;
    my $value = undef;

    # Exception for titles
    # If the title hasn't been found, construct it
    if ($field_name eq 'title')
    {
	$value = pagetitle(IkiWiki::basename($page));
    }
    elsif ($field_name eq 'pagetitle')
    {
	$value = pagetitle(IkiWiki::basename($page));
    }
    elsif ($field_name eq 'titlecaps')
    {
	$value = field_get_value('title', $page);
	$value =~ s/\.\w+$//; # remove extension
	$value =~ s/ (
		      (^\w)    #at the beginning of the line
		      |      # or
		      (\s\w)   #preceded by whitespace
		     )
	    /\U$1/xg;
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
	else # top-level page
	{
	    $value = 'index';
	}
    }
    elsif ($field_name eq 'basename')
    {
	$value = IkiWiki::basename($page);
    }
    return (wantarray ? ($value) : $value);
} # field_calculated_values

my %match_a_field_globs = ();

# match field funcs
# page-to-check, wanted
sub match_a_field ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.+)$/o)
    {
	$field_name = $1;
	$glob = $2;
    }
    else
    {
	return IkiWiki::FailReason->new("cannot match field");
    }

    # turn glob into a safe regexp
    if (!exists $match_a_field_globs{$glob})
    {
	my $re=IkiWiki::glob2re($glob);
	$match_a_field_globs{$glob} = qr/^$re$/i;
    }
    my $regexp = $match_a_field_globs{$glob};

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);

    if (defined $val) {
	if ($val=~$regexp) {
	    return IkiWiki::SuccessReason->new("$regexp matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
	}
	else {
	    return IkiWiki::FailReason->new("$regexp does not match $field_name of $page", "" => 1);
	}
    }
    else {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }
} # match_a_field

my %match_a_field_item_globs = ();

# check against individual items of a field
# (treat the field as an array)
# page-to-check, wanted
sub match_a_field_item ($$) {
    my $page=shift;
    my $wanted=shift;

    # The field name is first; the rest is the match
    my $field_name;
    my $glob;
    if ($wanted =~ /^(\w+)\s+(.+)$/o)
    {
	$field_name = $1;
	$glob = $2;
    }
    else
    {
	return IkiWiki::FailReason->new("cannot match field");
    }

    # turn glob into a safe regexp
    if (!exists $match_a_field_globs{$glob})
    {
	my $re=IkiWiki::glob2re($glob);
	$match_a_field_globs{$glob} = qr/^$re$/i;
    }
    my $regexp = $match_a_field_globs{$glob};

    my $val_loop = IkiWiki::Plugin::field::field_get_value("${field_name}_loop", $page);

    if ($val_loop)
    {
	foreach my $valhash (@{$val_loop})
	{
	    if (defined $valhash) {
		if ($valhash->{lc($field_name)} =~ $regexp) {
		    return IkiWiki::SuccessReason->new("$regexp matches $field_name of $page", $page => $IkiWiki::DEPEND_CONTENT, "" => 1);
		}
	    }
	}
	# not found
	return IkiWiki::FailReason->new("$regexp does not match $field_name of $page", "" => 1);
    }
    else {
	return IkiWiki::FailReason->new("$page does not have a $field_name", "" => 1);
    }
} # match_a_field_item

# ===============================================
# Data Source Objects
#
# Encapsulate this in an object.
# ---------------------------
package IkiWiki::Plugin::field::Source;

sub new {
    my $class = shift;
    my %parameters = @_;
    my $self = bless ({%parameters}, ref ($class) || $class);
    return ($self);
} # new

#
# These methods do the actual setting and getting.
# They can be overridden if one desires to use a different data source.
# The default source is to use the IkiWiki::pagestate hash.
#
# get ALL the values for a page
sub get_values {
    my ( $self, $page) = @_;

    return () unless defined $page;
    return () unless exists $IkiWiki::pagestate{$page}{field};
    return %{$IkiWiki::pagestate{$page}{field}};
} # get_values

# set ALL the values for a page
sub set_values {
    my ( $self, $page, %values) = @_;

    return 0 unless defined $page;
    return 0 unless %values;

    $IkiWiki::pagestate{$page}{field} = \%values;

    return scalar %values;
} # set_values

sub list_fields {
    my ( $self, $page) = @_;

    return () unless defined $page;
    return () unless exists $IkiWiki::pagestate{$page}{field};
    my @fields = (sort keys %{$IkiWiki::pagestate{$page}{field}});
    return @fields;
} # list_fields

sub get_value {
    my ( $self, $page, $field ) = @_;

    return undef unless defined $page and defined $field;
    return undef unless exists $IkiWiki::pagestate{$page}{field};
    return undef unless exists $IkiWiki::pagestate{$page}{field}{$field};
    return $IkiWiki::pagestate{$page}{field}{$field};
} # get_value

sub set_value {
    my ( $self, $page, $field, $value) = @_;

    return undef unless defined $page and defined $field and defined $value;

    my @values = ref $value ? @{$value} : ( $value );
    if (scalar @values == 1 and $field !~ /_loop/i)
    {
	$IkiWiki::pagestate{$page}{field}{$field} = $values[0];
    }
    else
    {
	$IkiWiki::pagestate{$page}{field}{$field} = \@values;
    }
    return scalar @values;
} # set_value

1;
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

    eval {use Sort::Naturally};
    error $@ if $@;

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    return Sort::Naturally::ncmp($left, $right);
}

1;
