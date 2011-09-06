#!/usr/bin/perl
# Ikiwiki field plugin.
package IkiWiki::Plugin::field;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::field - middle-end for per-page record fields.

=head1 VERSION

This describes version B<1.20110906> of IkiWiki::Plugin::field

=cut

our $VERSION = '1.20110906';

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

sub field_get_value ($$;@);

sub import {
	hook(type => "getsetup", id => "field",  call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "needsbuild", id => "field", call => \&needsbuild);
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

sub needsbuild (@) {
    my ($needsbuild, $deleted) = @_;

    # Non-page files need to have their fields cleared, because they won't
    # be re-scanned in the scan pass, and we know at this point
    # that they HAVE changed, so their data is out of date.
    foreach my $file (@{$needsbuild})
    {
	my $page=pagename($file);
	my $page_type = pagetype($file);
	if (!$page_type)
	{
	    if (exists $pagestate{$page}{field})
	    {
		delete $pagestate{$page}{field};
	    }
	}
    }
} # needsbuild

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
} # preprocess

sub scan (@) {
    my %params=@_;

    remember_values(%params);
    scan_for_tags(%params);
} # scan


sub pagetemplate (@) {
    my %params=@_;

    field_set_template_values($params{template}, $params{page});
} # pagetemplate

sub deleted (@) {
    my @files=@_;

    foreach my $file (@files)
    {
	my $page=pagename($file);
	delete $IkiWiki::pagestate{$page}{field};
    }
} # deleted

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

sub field_get_value ($$;@) {
    my $field_name = shift;
    my $page = shift;
    my %params = @_;

    # This expects all values to have been remembered in the scan pass.
    # However, non-pages will not have been scanned in the scan pass.
    # But non-pages could still have derived values, so check.

    my $pagesource = $pagesources{$page};
    return undef unless $pagesource;
    my $page_type = pagetype($pagesource);

    if (!$page_type and !fs_page_is_set($page))
    {
	remember_values(%params, page=>$page, content=>'');
    }

    my $lc_field_name = lc($field_name);

    if (exists $params{$lc_field_name})
    {
	my $value = $params{$lc_field_name};
	return $value;
    }
    else
    {
	my $value = fs_get_value($page, $lc_field_name);
	return $value;
    }
    return undef;
} # field_get_value

sub field_set_template_values ($$;@) {
    my $template = shift;
    my $page = shift;
    my %params = @_;

    # This expects all values to have been remembered in the scan pass.
    # However, non-pages will not have been scanned in the scan pass.
    # But non-pages could still have derived values, so check.
    my $pagesource = $pagesources{$page};
    return undef unless $pagesource;
    my $page_type = pagetype($pagesource);
    if (!$page_type and !fs_page_is_set($page))
    {
	remember_values(%params, page=>$page, content=>'');
    }

    my %vals = fs_get_values($page);
    if (%vals)
    {
	my @parameter_names = $template->param();
	foreach my $field (@parameter_names)
	{
	    # Don't redefine if the field already has a value set.
	    next if ($template->param($field));
	    # Passed-in parameters take precedence
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
} # field_set_template_values

# ===============================================
# Private Functions
# ---------------------------

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

    add_standard_values($page, $page_type);

    my %values = fs_get_values($page);
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
		format_values(
		    values => \%values,
		    field=>$lc_key,
		    value=> $vals{$key},
		    page_type=>$page_type,
		    page=>$page);
	    }
	}

	# Do this here so that later plugins can use the values.
	# This is so that one can have values derived from other values.
	fs_set_values($page, %values);

    } # for all registered field plugins

    add_derived_values($page, $page_type);
} # remember_values

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
sub add_standard_values {
    my $page = shift;
    my $page_type = shift;

    my %values = ();

    format_values(values=>\%values,
	field=>'page_type',
	value=>$page_type,
	page_type=>$page_type,
	page=>$page);

    my @fields = (qw(page parent_page basename));
    foreach my $key (@fields)
    {
	if (!$values{$key})
	{
	    my $val = calculated_values($key, $page);
	    format_values(values=>\%values,
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
	    if (!ref $config{$key} and defined $config{$key} and length $config{$key})
	    {
		$values{"config-${lc_key}"} = $config{$key};
	    }
	}
    }
    fs_set_values($page, %values);
} # add_standard_values

# standard values deduced from other values
# expects the values for the page to be set now
sub add_derived_values {
    my $page = shift;
    my $page_type = shift;

    my %values = fs_get_values($page);
    my @fields = (qw(title titlecaps pagetitle baseurl));
    foreach my $key (@fields)
    {
	if (!$values{$key})
	{
	    my $val = calculated_values($key, $page);
	    format_values(values=>\%values,
		field=>$key,
		value=>$val,
		page_type=>$page_type,
		page=>$page);
	    fs_set_values($page, %values);
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
	    my @tagpages = ();
	    my @loop = ();
	    my @orig_loop = @{$values{"${lc_key}_loop"}};
	    for (my $i = 0; $i < @orig_loop; $i++)
	    {
		my $tag = $orig_loop[$i]->{$lc_key};
		my $link = $config{field_tags}{$key} . '/' . titlepage($tag);
		$orig_loop[$i]->{"${lc_key}-tagpage"} = $link;
		push @loop, {$lc_key => $link};
		push @tagpages, $link;
	    }
	    $values{"${lc_key}-tagpage"} = join(' ', @tagpages);
	    $values{"${lc_key}-tagpage_loop"} = \@loop;
	    $values{"${lc_key}_loop"} = \@orig_loop;
	}
    }

    # set meta values if they haven't been set
    foreach my $key (qw{title description copyright author authorurl date updated})
    {
	if ((!exists $pagestate{$page}{meta}{$key}
		or !defined $pagestate{$page}{meta}{$key})
	    and exists $values{$key}
	    and defined $values{$key}
	    and $values{$key}
	)
	{
	    if ($key eq 'title' and exists $values{titlesort})
	    {
		IkiWiki::Plugin::meta::preprocess(
		    $key=>$values{$key},
		    sortas=>$values{titlesort},
		    page=>$page);
	    }
	    elsif ($key eq 'author' and exists $values{authorsort})
	    {
		IkiWiki::Plugin::meta::preprocess(
		    $key=>$values{$key},
		    sortas=>$values{authorsort},
		    page=>$page);
	    }
	    else
	    {
		IkiWiki::Plugin::meta::preprocess(
		    $key=>$values{$key},
		    page=>$page);
	    }
	}
    }

    fs_set_values($page, %values);
} # add_derived_values

# Add values in additional formats
# For example, _loop and _html
sub format_values {
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
} # format_values

# standard values deduced from other values
sub calculated_values {
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
    elsif ($field_name eq 'baseurl')
    {
	$value = IkiWiki::baseurl($page);
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
} # calculated_values

sub field_is_null ($$) {
    my $page=shift;
    my $field_name=shift;

    my $val = IkiWiki::Plugin::field::field_get_value($field_name, $page);

    # testing if the value is null, undefined etc.
    if (defined $val and $val) {
	return IkiWiki::FailReason->new("$field_name of $page is not null");
    }
    else {
	return IkiWiki::SuccessReason->new("$field_name of $page is null");
    }
} # field_is_null

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
# Field Source
# ---------------------------
# are values set for this page?
sub fs_page_is_set {
    my ($page) = @_;

    return 0 unless defined $page;
    return 0 unless exists $IkiWiki::pagestate{$page}{field};
    return 1;
} # fs_page_is_set

# get ALL the values for a page
sub fs_get_values {
    my ( $page) = @_;

    return () unless defined $page;
    return () unless exists $IkiWiki::pagestate{$page}{field};
    return %{$IkiWiki::pagestate{$page}{field}};
} # fs_get_values

# set ALL the values for a page
sub fs_set_values {
    my ( $page, %values) = @_;

    return 0 unless defined $page;
    return 0 unless %values;

    $IkiWiki::pagestate{$page}{field} = \%values;

    return scalar %values;
} # fs_set_values

sub fs_get_value {
    my ( $page, $field ) = @_;

    return undef unless defined $page and defined $field;
    return undef unless exists $IkiWiki::pagestate{$page}{field};
    return undef unless exists $IkiWiki::pagestate{$page}{field}{$field};
    return $IkiWiki::pagestate{$page}{field}{$field};
} # fs_get_value

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

sub match_field_null ($$;@) {
    my $page=shift;
    my $wanted=shift;
    return IkiWiki::Plugin::field::field_is_null($page, $wanted);
} # match_field_null

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
