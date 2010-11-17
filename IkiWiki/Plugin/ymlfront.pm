#!/usr/bin/perl
# YAML format for structured data
# See plugins/contrib/ymlfront for documentation.
package IkiWiki::Plugin::ymlfront;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::ymlfront - add YAML-format data to a page

=head1 VERSION

This describes version B<1.20100808> of IkiWiki::Plugin::ymlfront

=cut

our $VERSION = '1.20101116';

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field
    YAML::Any

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
	hook(type => "getsetup", id => "ymlfront", call => \&getsetup);
	hook(type => "checkconfig", id => "ymlfront", call => \&checkconfig);
	hook(type => "filter", id => "ymlfront", call => \&filter, first=>1);
	hook(type => "preprocess", id => "ymlfront", call => \&preprocess, scan=>1);
	hook(type => "scan", id => "ymlfront", call => \&scan);
	hook(type => "checkcontent", id => "ymlfront", call => \&checkcontent);

	IkiWiki::loadplugin('field');
	IkiWiki::Plugin::field::field_register(id=>'ymlfront',
					       call=>\&yml_get_value,
					       first=>1);
}

# ------------------------------------------------------------
# Package Vars
# --------------------------------
my $ymlfront_regex = qr{
	    (\\?)		# 1: escape?
		\[\[(!)		# directive open; 2: prefix
		(ymlfront)	# 3: command
		(		# 4: the parameters..
				\s+	# Must have space if parameters present
				(?:
				 (?:[-\w]+=)?		# named parameter key?
				 (?:
				  """.*?"""	# triple-quoted value
				  |
				  "[^"]*?"	# single-quoted value
				  |
				  [^"\s\]]+	# unquoted value
				 )
				 \s*			# whitespace or end
				 # of directive
				)
				*)?		# 0 or more parameters
		\]\]		# directive closed
	}sx;

# ------------------------------------------------------------
# Hooks
# --------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		ymlfront_delim => {
			type => "array",
			example => "ymlfront_sep => [qw(--YAML-START-- --YAML-END--)]",
			description => "delimiters of YAML data",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    eval q{use YAML::Any};
    eval q{use YAML} if $@;
    if ($@)
    {
	return error ("ymlfront: failed to use YAML::Any or YAML");
    }

    $YAML::UseBlock = 1;
    $YAML::Syck::ImplicitUnicode = 1;

    if (!defined $config{ymlfront_delim})
    {
	$config{ymlfront_delim} = [qw(--- ---)];
    }
} # checkconfig

# scan gets called before filter
sub scan (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return;
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return;
    }
    # clear the old data
    if (exists $pagestate{$page}{ymlfront})
    {
	delete $pagestate{$page}{ymlfront};
    }
    my $parsed_yml = parse_yml(%params);
    if (defined $parsed_yml
	and defined $parsed_yml->{yml})
    {
	# save the data to pagestate
	foreach my $fn (keys %{$parsed_yml->{yml}})
	{
	    my $fval = $parsed_yml->{yml}->{$fn};
	    $pagestate{$page}{ymlfront}{$fn} = $fval;
	}
    }
    # update meta hash
    if (exists $pagestate{$page}{ymlfront}{title}
	and $pagestate{$page}{ymlfront}{title})
    {
	$pagestate{$page}{meta}{title} = $pagestate{$page}{ymlfront}{title};
    }
    if (exists $pagestate{$page}{ymlfront}{description}
	and $pagestate{$page}{ymlfront}{description})
    {
	$pagestate{$page}{meta}{description} = $pagestate{$page}{ymlfront}{description};
    }
    if (exists $pagestate{$page}{ymlfront}{author}
	and $pagestate{$page}{ymlfront}{author})
    {
	$pagestate{$page}{meta}{author} = $pagestate{$page}{ymlfront}{author};
    }
} # scan

# use this for data in a [[!ymlfront ...]] directive
sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};

    if (! exists $params{data}
	or ! defined $params{data}
	or !$params{data})
    {
	error gettext("missing data parameter")
    }
    # All the work of this is done in scan mode;
    # when in preprocessing mode, just return an empty string.
    my $scan=! defined wantarray;

    if (!$scan)
    {
	return '';
    }

    # clear the old data
    if (exists $pagestate{$page}{ymlfront})
    {
	delete $pagestate{$page}{ymlfront};
    }
    my $parsed_yml = parse_yml(%params);
    if (defined $parsed_yml
	and defined $parsed_yml->{yml})
    {
	# save the data to pagestate
	foreach my $fn (keys %{$parsed_yml->{yml}})
	{
	    my $fval = $parsed_yml->{yml}->{$fn};
	    $pagestate{$page}{ymlfront}{$fn} = $fval;
	}
    }
    # update meta hash
    if (exists $pagestate{$page}{ymlfront}{title}
	and $pagestate{$page}{ymlfront}{title})
    {
	$pagestate{$page}{meta}{title} = $pagestate{$page}{ymlfront}{title};
    }
    if (exists $pagestate{$page}{ymlfront}{description}
	and $pagestate{$page}{ymlfront}{description})
    {
	$pagestate{$page}{meta}{description} = $pagestate{$page}{ymlfront}{description};
    }
    if (exists $pagestate{$page}{ymlfront}{author}
	and $pagestate{$page}{ymlfront}{author})
    {
	$pagestate{$page}{meta}{author} = $pagestate{$page}{ymlfront}{author};
    }
    return '';
} # preprocess

sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return $params{content};
    }
    my $parsed_yml = parse_yml(%params);
    if (defined $parsed_yml
	and defined $parsed_yml->{yml}
	and defined $parsed_yml->{content})
    {
	$params{content} = $parsed_yml->{content};
	# also check for a content value
	if (exists $pagestate{$page}{ymlfront}{content}
	    and defined $pagestate{$page}{ymlfront}{content}
	    and $pagestate{$page}{ymlfront}{content})
	{
	    $params{content} .= $pagestate{$page}{ymlfront}{content};
	}
    }

    return $params{content};
} # filter

# check the correctness of the YAML code before saving a page
sub checkcontent {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page};
    if ($page_file)
    {
	my $page_type=pagetype($page_file);
	if (!defined $page_type)
	{
	    return undef;
	}
    }
    my $parsed_yml = parse_yml(%params);
    if (!defined $parsed_yml)
    {
	debug("ymlfront: Save of $page failed: $@");
	return gettext("YAML data incorrect: $@");
    }
    return undef;
} # checkcontent

# ------------------------------------------------------------
# Field functions
# --------------------------------
sub yml_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    my $value = undef;
    if (exists $pagestate{$page}{ymlfront}{$field_name})
    {
	$value = $pagestate{$page}{ymlfront}{$field_name};
    }
    elsif (exists $pagestate{$page}{ymlfront}{lc($field_name)})
    {
	$value = $pagestate{$page}{ymlfront}{lc($field_name)};
    }
    if (defined $value)
    {
	if (ref $value)
	{
	    my @value_array = @{$value};
	    return (wantarray
		    ? @value_array
		    : join(",", @value_array));
	}
	else
	{
	    return (wantarray ? ($value) : $value);
	}
    }
    return undef;
} # yml_get_value

# ------------------------------------------------------------
# Helper functions
# --------------------------------

# parse the YAML data from the given content
# Expects page, content
# Returns { yml=>%yml_data, content=>$content } or undef
sub parse_yml {
    my %params=@_;
    my $page = $params{page};
    my $content = $params{content};

    my $page_file=$pagesources{$page};
    if ($page_file)
    {
	my $page_type=pagetype($page_file);
	if (!defined $page_type)
	{
	    return undef;
	}
    }
    my $start_of_content = '';
    my $yml_str = '';
    my $rest_of_content = '';
    if ($params{data})
    {
	$yml_str = $params{data};
    }
    elsif ($content)
    {
	my $ystart = $config{ymlfront_delim}[0];
	my $yend = $config{ymlfront_delim}[1];
	if ($ystart eq '---'
	    and $yend eq '---'
	    and $content =~ /^---[\n\r](.*?[\n\r])---[\n\r](.*)$/s)
	{
	    $yml_str = $1;
	    $rest_of_content = $2;
	}
	elsif ($content =~ /^(.*?)${ystart}[\n\r](.*?[\n\r])${yend}([\n\r].*)$/s)
	{
	    $yml_str = $2;
	    $rest_of_content = $1 . $3;
	} 
	elsif ($content =~ $ymlfront_regex)
	{
	    my $escape=$1;
	    my $prefix=$2;
	    my $command=$3;
	    my $params=$4;
	    if ($escape)
	    {
		$rest_of_content = $content;
	    }
	    else
	    {
		my %phash = ();
		while ($params =~ m{
		       (?:([-\w]+)=)?		# 1: named parameter key?
		       (?:
			"""(.*?)"""	# 2: triple-quoted value
			|
			"([^"]*?)"	# 3: single-quoted value
			|
			(\S+)		# 4: unquoted value
		       )
		       (?:\s+|$)		# delimiter to next param
		       }sgx) {
		    my $key=$1;
		    my $val;
		    if (defined $2) {
			$val=$2;
			$val=~s/\r\n/\n/mg;
			$val=~s/^\n+//g;
			$val=~s/\n+$//g;
		    }
		    elsif (defined $3) {
			$val=$3;
		    }
		    elsif (defined $4) {
			$val=$4;
		    }

		    if (defined $key) {
			$phash{$key} = $val;
		    }
		    else {
			$phash{''} = $val;
		    }
		}
		if (defined $phash{data})
		{
		    $yml_str = $phash{data};
		    $content =~ /^(.*?)\[\[!ymlfront.*?\]\](.*?)$/s;
		    $start_of_content = $1;
		    $rest_of_content = $2;
		}
	    }
	}
    }
    if ($yml_str)
    {
	# if {{$page}} is there, do an immediate substitution
	$yml_str =~ s/\{\{\$page\}\}/$page/sg;

	my $ydata;
	eval q{$ydata = Load($yml_str);};
	if ($@)
	{
	    debug("ymlfront: Load of $page failed: $@");
	    return undef;
	}
	if (!$ydata)
	{
	    debug("ymlfront: no YAML for $page");
	    return undef;
	}
	my %lc_data = ();
	if ($ydata)
	{
	    # make lower-cased versions of the data
	    foreach my $fn (keys %{$ydata})
	    {
		my $fval = $ydata->{$fn};
		$lc_data{lc($fn)} = $fval;
	    }
	}
	return { yml=>\%lc_data,
	    content=>$start_of_content . $rest_of_content};
    }
    return { yml=>undef, content=>$content };
} # parse_yml
1;
