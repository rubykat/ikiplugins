#!/usr/bin/perl
# swish-e search engine plugin
package IkiWiki::Plugin::swishe;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Basename;
use Carp;
require CGI;

sub import {
	hook(type => "getopt", id => "tag", call => \&getopt);
	hook(type => "getsetup", id => "swishe", call => \&getsetup);
	hook(type => "checkconfig", id => "swishe", call => \&checkconfig);
	hook(type => "preprocess", id => "swishe", call => \&preprocess);
	hook(type => "pagetemplate", id => "swishe", call => \&pagetemplate);
	hook(type => "cgi", id => "swishe", call => \&cgi);
}

sub getopt () {
	eval {use Getopt::Long};
	error($@) if $@;
	Getopt::Long::Configure('pass_through');
	GetOptions("swishe_run!" => \$config{swishe_run},
	"swishe_run_config=s" => \$config{swishe_run_config}
    );
}

sub getsetup () {
    return
    plugin => {
	safe => 1,
	rebuild => 1,
	section => "web",
    },
    swishe_mods => {
	type => "string",
	example => "/usr/lib/swish-e/perl",
	description => "path to the swish-e perl helper modules",
	safe => 0,
	rebuild => 0,
    },
    swishe_binary => {
	type => "string",
	example => "/usr/bin/swish-e",
	description => "path to the swish-e program",
	safe => 0,
	rebuild => 0,
    },
    swishe_index => {
	type => "string",
	example => "/var/www/web_src/.ikiwiki/swishe/index.swish-e",
	description => "path to the swish-e index file",
	safe => 0,
	rebuild => 0,
    },
    swishe_page_size => {
	type => "string",
	example => "10",
	description => "number of results per page",
	safe => 0,
	rebuild => 0,
    },
}

sub checkconfig () {
    foreach my $required (qw(url cgiurl)) {
	if (! length $config{$required}) {
	    error(sprintf(gettext("Must specify %s when using the %s plugin"), $required, 'swishe'));
	}
    }

    if (! defined $config{swishe_binary}) {
	$config{swishe_binary}="/usr/bin/swish-e";
    }
    if (!-f $config{swishe_binary})
    {
	error(sprintf(gettext("%s does not exist; needed for %s plugin"), $config{swishe_binary}, 'swishe'));
    }
    if (! defined $config{swishe_index}) {
	$config{swishe_index} = "$config{wikistatedir}/swishe/index.swish-e";
    }

    # ------------------------------------------------------------
    # If swishe_run is true, then run swish-e and exit
    #
    if ($config{swishe_run})
    {
	my ($name,$path,$suffix) = fileparse($config{swishe_index},'');
	if (!-d $path)
	{
	    mkdir $path;
	}
	chdir $path;
	my @command = ($config{swishe_binary},
	    '-c', $config{swishe_run_config},
	    '-i', $config{destdir},
	);
	push @command, ('-v', '1') if $config{verbose};
	if (system(@command) != 0)
	{
	    die sprintf("swishe_run '%s' FAILED: %s", join(' ', @command), $@);
	}
	else
	{
	    exit 0;
	}
    }

    # ------------------------------------------------------------
    # NOT running swish-e

    if (! defined $config{swishe_mods}) {
	$config{swishe_mods}="/usr/lib/swish-e/perl";
    }
    if (!-d $config{swishe_mods})
    {
	error(sprintf(gettext("%s is not a directory; needed for %s plugin"), $config{swishe_mods}, 'swishe'));
    }
    eval q{use lib ( "$config{swishe_mods}" );};
    if ($@)
    {
	error(sprintf(gettext("use lib failed for %s; needed for %s plugin"), $config{swishe_mods}, 'swishe'));
	return 0;
    }
    if (! defined $config{swishe_page_size}) {
	$config{swishe_page_size} = 15;
    }
    if (! defined $config{swishe_title}) {
	$config{swishe_title} = 'Search';
    }
    if (! defined $config{swishe_title_property}) {
	$config{swishe_title_property} = 'swishtitle';
    }
    if (! defined $config{swishe_description_prop}) {
	$config{swishe_description_prop} = 'swishdescription';
    }
    if (! defined $config{swishe_link_property}) {
	$config{swishe_link_property} = 'swishdocpath';
    }
    if (! defined $config{swishe_display_props}) {
        $config{swishe_display_props}   = [qw/swishlastmodified swishdocsize swishdocpath/];
    }
    if (! defined $config{swishe_sorts}) {
        $config{swishe_sorts} = [qw/swishrank swishlastmodified swishtitle swishdocpath/];
    }
    if (! defined $config{swishe_secondary_sort}) {
        $config{swishe_secondary_sort} = [qw/swishlastmodified desc/];
    }
    if (! defined $config{swishe_metanames}) {
        $config{swishe_metanames} = [qw/swishdefault swishtitle swishdocpath all/];
    }
    if (! defined $config{swishe_meta_groups}) {
        $config{swishe_meta_groups} = {
            all =>  [qw/swishdefault swishtitle swishdocpath/],
	}
    }
    if (! defined $config{swishe_name_labels}) {
        $config{swishe_name_labels} = {
            swishdefault        => 'Title & Body',
            swishtitle          => 'Title',
            swishrank           => 'Rank',
            swishlastmodified   => 'Last Modified Date',
            swishdocpath        => 'Document Path',
            swishdocsize        => 'Document Size',
            all                 => 'All',              # group of metanames
            subject             => 'Message Subject',  # other examples
            name                => "Poster's Name",
            email               => "Poster's Email",
            sent                => 'Message Date',
        };
    }
    if (! defined $config{swishe_timeout}) {
        $config{swishe_timeout} = 10;
    }
    if (! defined $config{swishe_max_query_length}) {
        $config{swishe_max_query_length} = 100;
    }
    if (! defined $config{swishe_max_chars}) {
        $config{swishe_max_chars} = 500;
    }

    if (! defined $config{swishe_highlight}) {
	$config{swishe_highlight} = {
	    package	    => 'SWISH::PhraseHighlight',
	    show_words      => 10,
	    max_words       => 100,
	    occurrences     => 6,
	    highlight_on    => '<em>',
	    highlight_off   => '</em>',
	}
    }
    if (! defined $config{swishe_highlight_meta_to_prop_map}) {
	$config{swishe_highlight_meta_to_prop_map} = {
	    swishdefault => [ qw/swishtitle swishdescription/ ],
	    swishtitle => [ qw/swishtitle/ ],
	    swishdocpath => [ qw/swishdocpath/ ],
	};
    }

    if (! defined $config{swishe_no_first_page_navigation}) {
        $config{swishe_no_first_page_navigation} = 0;
    }
    if (! defined $config{swishe_no_last_page_navigation}) {
        $config{swishe_no_last_page_navigation} = 0;
    }
    if (! defined $config{swishe_num_pages_to_show}) {
        $config{swishe_num_pages_to_show} = 12;
    }
#    $config{swishe_date_ranges} = {
#	property_name   => 'swishlastmodified',
#	time_periods    => [
#	    'All',
#	    'Today',
#	    'Yesterday',
#	    'This Week',
#	    'Last Week',
#	    'Last 90 Days',
#	    'This Month',
#	    'Last Month',
#	],
#	line_break      => 0,
#	default         => 'All',
#	date_range      => 1,
#    };

    # This is a mass dependency, so if the swishe form template
    # changes, every page is rebuilt.
    add_depends("", "templates/swishe_form.tmpl");

}

sub preprocess (@) {
    my %params=@_;
    my $page=$params{page};

    my $search = SwishQuery->new(
	config    => \$IkiWiki::config,
	request   => CGI->new()
    );
    my $meta_select_list    = $search->get_meta_name_limits();
    my $sorts               = $search->get_sort_select_list();
    my $select_index        = $search->get_index_select_list();
    my $limit_select        = $search->get_limit_select();
    my $date_ranges_select  = $search->get_date_ranges();

    my $template;
    eval {
	$template=IkiWiki::template("swishe_advanced.tmpl",
	    blind_cache => 1);
    };
    if ($@) {
	croak "failed to process template swishe_advanced.tmpl: $@";
    }
    if (! $template) {
	croak sprintf("%s not found", "/templates/swishe_advanced.tmpl");
    }

    $template->param(searchaction => IkiWiki::cgiurl());
    $template->param(TITLE=>$IkiWiki::config{swishe_title});
    $template->param(META_SELECT=>$meta_select_list);
    $template->param(SORTS=>$sorts);
    $template->param(LIMIT_SELECT=>$limit_select);
    $template->param(DATE_RANGES=>$date_ranges_select);
    $template->param(SELECT_INDEX=>$select_index);

    return $template->output;
} # preprocess

my $form;
sub pagetemplate (@) {
    my %params=@_;
    my $page=$params{page};
    my $template=$params{template};

    # Add search box to page header.
    if ($template->query(name => "searchform")) {
	if (! defined $form) {
	    my $swisheform = template("swishe_form.tmpl", blind_cache => 1);
	    $swisheform->param(searchaction => IkiWiki::cgiurl());
	    $swisheform->param(html5 => $config{html5});
	    $form=$swisheform->output;
	}

	$template->param(searchform => $form);
    }
}

sub cgi ($) {
    my $cgi=shift;

    if (defined $cgi->param('query')) {
	my $search = SwishQuery->new(
	    config    => \$IkiWiki::config,
	    request   => $cgi,
	);
	$search->run_query;

	if ( $search->hits ) {
	    $search->set_navigation;
	}

	print $cgi->header;
	print $search->generate_view();
	exit;
    }
}

#=============================================================================
package SwishQuery;
# - based on swishe.cgi
#=============================================================================

use IkiWiki 3.00;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser);

#----------------------------------------------------------------------------
# new() doesn't do much, just create the object
#----------------------------------------------------------------------------
sub new {
    my $class = shift;
    my %options = @_;

    warningsToBrowser(0);

    my $conf = \%IkiWiki::config;

    if (! defined $conf->{swishe_mods}) {
	$conf->{swishe_mods}="/usr/lib/swish-e/perl";
    }
    if (!-d $conf->{swishe_mods})
    {
	croak (sprintf("%s is not a directory; needed for %s plugin", $conf->{swishe_mods}, 'swishe'));
    }
    eval q{use lib ( "$conf->{swishe_mods}" );};
    if ($@)
    {
	croak (sprintf("use lib failed for %s; needed for %s plugin", $conf->{swishe_mods}, 'swishe'));
    }
    load_module('SWISH::API');
    load_module('SWISH::ParseQuery');
    load_module('SWISH::DateRanges');

    # initialize the request search hash
    my $sh = {
       prog         => $conf->{swishe_binary},
       config       => $conf,
       q            => $options{request},
       hits         => 0,
       MOD_PERL     => $ENV{MOD_PERL},
    };

    my $self = bless $sh, $class;

    # load highlight module, if requsted

    if ( my $highlight = $self->config('swishe_highlight') ) {
        $highlight->{package} ||= 'SWISH::DefaultHighlight';
        load_module( $highlight->{package} );
    }

    # Fetch the swish-e query from the CGI parameters
    $self->set_query;

    return $self;
}

sub load_module {
    my $package = shift;
    $package =~ s[::][/]g;
    eval { require "$package.pm" };
    if ( $@ ) {
        print <<EOF;
Content-Type: text/html

<html>
<head><title>Software Error</title></head>
<body><h2>Software Error</h2><p>Please check error log</p></body>
</html>
EOF

        die "$0 $@\n";
    }
}


sub hits { shift->{hits} }

sub config {
    my ($self, $setting, $value ) = @_;

    confess "Failed to pass 'config' a setting" unless $setting;

    my $cur = $self->{config}{$setting} if exists $self->{config}{$setting};

    $self->{config}{$setting} = $value if $value;

    return $cur;
}

# Returns false if all of @values are not valid options - for checking
# $config is what $self->config returns

sub is_valid_config_option {
    my ( $self, $config, $err_msg, @values ) = @_;

    unless ( $config ) {
        $self->errstr( "No config option set: $err_msg" );
        return;
    }

    # Allow multiple values.
    my @options = ref $config eq 'ARRAY' ? @$config : ( $config );

    my %lookup = map { $_ => 1 } @options;

    for ( @values ) {
        unless ( exists $lookup{ $_ } ) {
            $self->errstr( $err_msg );
            return;
        }
    }

    return 1;
}

sub header {
    my $self = shift;
    return unless ref $self->{_headers} eq 'HASH';

    return $self->{_headers}{$_[0]} || '';
}

# return a ref to an array
sub results {
    my $self = shift;
    return $self->{_results} || [];
}

sub navigation {
    my $self = shift;
    return unless ref $self->{navigation} eq 'HASH';

    return exists $self->{navigation}{$_[0]} ? $self->{navigation}{$_[0]} : '';
}

sub CGI { $_[0]->{q} };

sub swishe_command {

    my ($self, $param_name, $value ) = @_;

    return $self->{swishe_command} || {} unless $param_name;
    return $self->{swishe_command}{$param_name} || '' unless $value;

    $self->{swishe_command}{$param_name} = $value;
}

# For use when forking

sub swishe_command_array {

    my ($self ) = @_;

    my @params;
    my $swishe_command = $self->swishe_command;

    for ( keys %$swishe_command ) {

        my $value = $swishe_command->{$_};

        if ( /^-/ ) {
            push @params, $_;
            push @params, ref $value eq 'ARRAY' ? @$value : $value;
            next;
        }

        # special cases
        if ( $_ eq 'limits' ) {
            push @params, '-L', $value->{prop}, $value->{low}, $value->{high};
            next;
        }

        die "Unknown swishe_command '$_' = '$value'";
    }

    return @params;

}

sub errstr {
    my ($self, $value ) = @_;


    $self->{_errstr} = $value if $value;

    return $self->{_errstr} || '';
}


#==============================================================================
# Set query from the CGI parameters
#------------------------------------------------------------------------------

sub set_query {
    my $self = shift;
    my $q = $self->{q};

    # Sets the query string, and any -L limits.
    return unless $self->build_query;

    # Set the starting position (which is offset by one)

    my $start = $q->param('start') || 0;
    $start = 0 unless $start =~ /^\d+$/ && $start >= 0;

    $self->swishe_command( '-b', $start+1 );

    # Set the max hits
    my $page_size = $self->config('swishe_page_size') || 15;
    $self->swishe_command( '-m', $page_size );

    return unless $self->set_index_file;

    # Set the sort option, if any
    return unless $self->set_sort_order;

    return 1;
}

#============================================
# This returns "$self" just in case we want to seperate out into two objects later

sub run_query {

    my $self = shift;

    my $q = $self->{q};
    my $conf = $self->{config};

    return $self unless $self->swishe_command('-w');

    my $time_out_str = 'Timed out';


    my $timeout = $self->config('swishe_timeout') || 0;

    eval {
        local $SIG{ALRM} = sub {
            kill 'KILL', $self->{pid} if $self->{pid};
            die $time_out_str . "\n";
        };

        alarm $timeout if $timeout && $^O !~ /Win32/i;
        $self->run_swishe;
        alarm 0  unless $^O =~ /Win32/i;

        # catch zombies
        waitpid $self->{pid}, 0 if $self->{pid};  # for IPC::Open2
    };

    if ( $@ ) {
        warn "$0 aborted: $@"; # if $conf->{swishe_debug};

        $self->errstr(
            $@ =~ /$time_out_str/
            ? "Search timed out after $timeout seconds."
            : "Service currently unavailable"
        );
        return $self;
    }
}


# Build href for repeated search via GET (forward, backward links)

sub set_navigation {
    my $self = shift;
    my $q = $self->{q};

    # Single string

    # default fields
    my @std_fields = qw/query metaname sort reverse/;

    # Extra fields could be added in the config file
    if ( my $extra = $self->config('swishe_extra_fields') ) {
        push @std_fields, @$extra;
    }

    my @query_string =
         map { "$_=" . $q->escape( $q->param($_) ) }
            grep { $q->param($_) }  @std_fields;

    # Perhaps arrays

    for my $p ( qw/si sbm/ ) {
        my @settings = $q->param($p);
        next unless @settings;
        push @query_string,  "$p=" . $q->escape( $_ ) for @settings;
    }

    if ( $self->config('swishe_date_ranges' ) ) {
        my $dr = SWISH::DateRanges::GetDateRangeArgs( $q );
        push @query_string, $dr, if $dr;
    }

    $self->{query_href} = $q->script_name . '?' . join '&amp;', @query_string;
    $self->{my_url} = $q->script_name;

    my $hits = $self->hits;

    my $start = $self->swishe_command('-b') || 1;
    $start--;

    $self->{navigation}  = {
            showing     => $hits,
            from        => $start + 1,
            to          => $start + $hits,
            hits        => $self->header('number of hits') ||  0,
            run_time    => $self->header('run time') ||  'unknown',
            search_time => $self->header('search time') ||  'unknown',
    };

    $self->set_page ( $self->swishe_command( '-m' ) );

    return $self;

}


#============================================================
# Build a query string from swishe
# Just builds the -w string
#------------------------------------------------------------

sub build_query {
    my $self = shift;

    my $q = $self->{q};


    # set up the query string to pass to swishe.
    my $query = $q->param('query') || '';

    for ( $query ) {  # trim the query string
        s/\s+$//;
        s/^\s+//;
    }

    $self->{query_simple} = $query;    # without metaname
    $q->param('query', $query );  # clean up the query, if needed.


    # Read in the date limits, if any.  This can create a new query, which is why it is here
    return unless $self->get_date_limits( \$query );


    unless ( $query ) {
	#$self->errstr('Please enter a query string') if $q->param('submit');
        $self->errstr('Please enter a query string');
        return;
    }

    if ( length( $query ) > $self->{config}{swishe_max_query_length} ) {
        $self->errstr('Please enter a shorter query');
        return;
    }

    # Adjust the query string for metaname search
    # *Everything* is a metaname search
    # Might also like to allow searching more than one metaname at the same time

    my $metaname = $q->param('metaname') || 'swishdefault';

    return unless $self->is_valid_config_option( $self->config('swishe_metanames') || 'swishdefault', 'Bad MetaName provided', $metaname );

    # save the metaname so we know what field to highlight
    # Note that this might be a fake metaname
    $self->{metaname} = $metaname;


    # prepend metaname to query

    # expand query when using meta_groups

    my $meta_groups = $self->config('swishe_meta_groups');

    if ( $meta_groups && $meta_groups->{$metaname} ) {
        $query = join ' OR ', map { "$_=($query)" } @{$meta_groups->{$metaname}};

        # This is used to create a fake entry in the parsed query so highlighting
        # can find the query words
        $self->{real_metaname} = $meta_groups->{$metaname}[0];
    } else {
        $query = $metaname . "=($query)";
    }




    ## Look for a "limit" metaname -- perhaps used with ExtractPath
    # Here we don't worry about user supplied data

    my $limits = $self->config('swishe_select_by_meta');
    my @limits = $q->param('sbm');  # Select By Metaname


    # Note that this could be messed up by ending the query in a NOT or OR
    # Should look into doing:
    # $query = "( $query ) AND " . $limits->{metaname} . '=(' . join( ' OR ', @limits ) . ')';

    if ( @limits && ref $limits eq 'HASH' && $limits->{metaname} ) {
        $query .= ' and ' . $limits->{metaname} . '=(' . join( ' or ', @limits ) . ')';
    }


    $self->swishe_command('-w', $query );

    return 1;
} # build_query

#========================================================================
#  Get the index files from the form, or from the config settings
#  Uses index numbers to hide path names
#------------------------------------------------------------------------

sub set_index_file {
    my $self = shift;

    my $q = $self->CGI;

    # Set the index file - first check for options

    my $si =  $self->config('swishe_select_indexes');
    if ( $si && ref $self->config('swishe_index') eq 'ARRAY'  ) {

        my @choices = $q->param('si');

        if ( !@choices ) {

           if ( $si->{default_index} ) {
               $self->swishe_command('-f', $si->{'default_index'});
               return 1;

            } else {
                $self->errstr('Please select a source to search');
                return;
            }
        }

        my @indexes = @{$self->config('swishe_index')};


        my @selected_indexes = grep {/^\d+$/ && $_ >= 0 && $_ < @indexes } @choices;

        if ( !@selected_indexes ) {
            $self->errstr('Invalid source selected');
            return $self;
        }
        my %dups;
        my @idx = grep { !$dups{$_}++ } map { ref($_) ? @$_ : $_ } @indexes[ @selected_indexes ];
        $self->swishe_command( '-f', \@idx );


    } else {
        $self->swishe_command( '-f', $self->config('swishe_index') );
    }

    return 1;
}

#================================================================================
#   Parse out the date limits from the form or from GET request
#
#---------------------------------------------------------------------------------

sub get_date_limits {

    my ( $self, $query_ref ) = @_;  # reference to query since may be modified

    my $conf = $self->{config};

    # Are date ranges enabled?
    return 1 unless $conf->{date_ranges};


    eval { require SWISH::DateRanges };
    if ( $@ ) {
        warn "\n------ Can't use DateRanges feature ------------\n",
                     "\nScript will run, but you can't use the date range feature\n",
                     $@,
                     "\n--------------\n" if $conf->{swishe_debug};

        delete $conf->{date_ranges};
        return 1;
    }

    my $q = $self->{q};

    my %limits;

    unless ( SWISH::DateRanges::DateRangeParse( $q, \%limits ) ) {
        $self->errstr( $limits{dr_error} || 'Bad date range selection' );
        return;
    }

    # Store the values for later (for display on templates)

    $self->{DateRanges_time_low} = $limits{dr_time_low};
    $self->{DateRanges_time_high} = $limits{dr_time_high};


    # Allow searchs just be date if not "All dates" search
    # $$$ should place some limits here, and provide a switch to disable
    # as it can bring up a lot of results.

    $$query_ref ||= 'not skaiqwdsikdeekk'
        if $limits{dr_time_high};


    # Now specify limits, if a range was specified

    my $limit_prop = $conf->{date_ranges}{property_name} || 'swishlastmodified';


    if ( $limits{dr_time_low} && $limits{dr_time_high} ) {

        my %limits = (
            prop    => $limit_prop,
            low     => $limits{dr_time_low},
            high    => $limits{dr_time_high},
        );

        $self->swishe_command( 'limits', \%limits );
    }

    return 1;
}



#================================================================
#  Set the sort order
#  Just builds the -s string
#----------------------------------------------------------------

sub set_sort_order {
    my $self = shift;

    my $q = $self->{q};

    my $sorts_array = $self->config('swishe_sorts');
    my $sortby =  $q->param('sort') || '';

    return 1 unless $sorts_array && $sortby;
    return unless $self->is_valid_config_option( $sorts_array, 'Invalid Sort Option Selected', $sortby );


    my $conf = $self->{config};


    # Now set sort option - if a valid option submitted (or you could let swish-e return the error).
    my $direction = $sortby eq 'swishrank'
        ? $q->param('reverse') ? 'asc' : 'desc'
        : $q->param('reverse') ? 'desc' : 'asc';

    my @sort_params = ( $sortby, $direction );

    if ( $conf->{secondary_sort} ) {
        my @secondary = ref $conf->{secondary_sort} ? @{ $conf->{secondary_sort} } : $conf->{secondary_sort};

        push @sort_params, @secondary
            if $sortby ne $secondary[0];
    }


    $self->swishe_command( '-s', \@sort_params );


    return 1;
}



#========================================================
# Sets prev and next page links.
# Feel free to clean this code up!
#
#   Pass:
#       $results - reference to a hash (for access to the headers returned by swishe)
#       $q       - CGI object
#
#   Returns:
#       Sets entries in the $results hash
#

sub set_page {

    my ( $self, $Page_Size ) = @_;

    my $q = $self->{q};
    my $config = $self->{config};

    my $navigation = $self->{navigation};


    my $start = $navigation->{from} - 1;   # Current starting record index


    # Set start number for "prev page" and the number of hits on the prev page

    my $prev = $start - $Page_Size;
    $prev = 0 if $prev < 0;

    if ( $prev < $start ) {
        $navigation->{prev} = $prev;
        $navigation->{prev_count} = $start - $prev;
    }


    my $last = $navigation->{hits} - 1;


    # Set start number for "next page" and number of hits on the next page

    my $next = $start + $Page_Size;
    $next = $last if $next > $last;
    my $cur_end   = $start + $self->{hits} - 1;
    if ( $next > $cur_end ) {
        $navigation->{next} = $next;
        $navigation->{next_count} = $next + $Page_Size > $last
                                ? $last - $next + 1
                                : $Page_Size;
    }


    # Calculate pages  ( is this -1 correct here? )
    # Build an array of a range of page numbers.

    my $total_pages = int (($navigation->{hits} -1) / $Page_Size);  # total pages for all results.

    if ( $total_pages ) {

        my @pages = 0..$total_pages;

        my $show_pages = $config->{swishe_num_pages_to_show} || 12;

        # To make the number always work
        $show_pages-- unless $config->{swishe_no_first_page_navigation};
        $show_pages-- unless $config->{swishe_no_last_page_navigation};


        # If too many pages then limit

        if ( @pages > $show_pages ) {

            my $start_page = int ( $start / $Page_Size - $show_pages/2) ;
            $start_page = 0 if $start_page < 0;

            # if close to the end then move of center
            $start_page = $total_pages - $show_pages
                if $start_page + $show_pages - 1 > $total_pages;

            @pages = $start_page..$start_page + $show_pages - 1;


            # Add first and last pages, unless config says otherwise
            unshift @pages, 0
                unless $start_page == 0 || $config->{swishe_no_first_page_navigation};

            push @pages, $total_pages
                unless $start_page + $show_pages - 1 == $total_pages || $config->{swishe_no_last_page_navigation}
        }


        # Build "canned" pages HTML

        $navigation->{pages} =
            join ' ', map {
                my $page_start = $_ * $Page_Size;
                my $page = $_ + 1;
                $page_start == $start
                ? $page
                : qq[<a href="$self->{query_href}&amp;start=$page_start">$page</a>];
                        } @pages;


        # Build just the raw data - an array of hashes
        # for custom page display with templates

        $navigation->{page_array} = [
            map {
                    {
                        page_number     => $_ + 1,  # page number to display
                        page_start      => $_ * $Page_Size,
                        cur_page        => $_ * $Page_Size == $start,  # flag
                    }
                } @pages
        ];


    }

}

#==================================================
# Format and return the date range options in HTML
#
#--------------------------------------------------
sub get_date_ranges {
    my $self = shift;

    my $q = $self->{q};
    my $conf = $self->{config};

    return '' unless $conf->{swishe_date_ranges};

    # pass parametes, and a hash to store the returned values.

    my %fields;

    SWISH::DateRanges::DateRangeForm( $q, $conf->{swishe_date_ranges}, \%fields );


    # Set the layout:

    my $string = '<br>Limit to: '
                 . ( $fields{buttons} ? "$fields{buttons}<br>" : '' )
                 . ( $fields{date_range_button} || '' )
                 . ( $fields{date_range_low}
                     ? " $fields{date_range_low} through $fields{date_range_high}"
                     : '' );

    return $string;
}



#============================================
# Run swish-e and gathers headers and results
# Currently requires fork() to run.
#
#   Pass:
#       $sh - an array with search parameters
#
#   Returns:
#       a reference to a hash that contains the headers and results
#       or possibly a scalar with an error message.
#


sub run_swishe {


    my $self = shift;

    my $results = $self->{results};
    my $conf    = $self->{config};
    my $q       = $self->{q};


    my @properties;
    my %seen;

    # Gather up the properties we need in results

    for ( qw/ swishe_title_property swishe_description_prop swishe_display_props swishe_link_property/ ) {
        push @properties, ref $conf->{$_} ? @{$conf->{$_}} : $conf->{$_}
            if $conf->{$_} && !$seen{$_}++;
    }

    # Add in the default props that should be seen.
    for ( qw/swishrank/ ) {
        push @properties, $_ unless $seen{$_};
    }


    # add in the default prop - a number must be first (this might be a duplicate in -x, oh well)
    unshift @properties, 'swishreccount';


    $self->swishe_command( -x => join( '\t', map { "<$_>" } @properties ) . '\n' );
    $self->swishe_command( -H => 9 );


    if ( $conf->{swishe_debug}) {
        require YAML::Any;
        warn "---- Swish parameters ----\n" .
        YAML::Any::Dump($self->swishe_command) .
        "\n-----------------------------------------------\n";
    }

    return $self->run_library( @properties );
}

# Filters in place
sub html_escape {
    $_[0] = '' unless defined $_[0];
    for ($_[0]) {
        s/&/&amp;/g;
        s/</&lt;/g;
        s/>/&gt;/g;
        s/"/&quot;/g;
    }
}


#============================================================================
# Adds a result to the result list and highlight the search words

# This is a common source of bugs!  The problem is that highlighting is done in
# this code.  This is good, especially for the description because it is
# trimmed down as processing each result.  Otherwise, would use a lot of
# memory. It's bad because the highlighting is creating html which really
# should be done in the template output code.  What that means is the
# properties that are "searched" are run through the highlighting code (and
# thus HTML escaped) but other properties are not.  If highlighting (and
# trimming) is to be kept here then either we need to html escape all display
# properties, or flag which ones are escaped.  Since we know the ultimate
# output is HTML, the current method will be to escape here.


sub add_result_to_list {
    my ( $self, $props ) = @_;

    $props->{swishtitle} = $props->{swishdocpath} if !$props->{swishtitle};

    # We need to save the text of the link prop (almost always swishdocpath)
    # because all properties are escaped.

    my $link_property = $self->config('swishe_link_property') || 'swishdocpath';
    my $link_href = ( $self->config('swishe_prepend_path') || '' )
                                  . $props->{$link_property};

    # Replace spaces ***argh this is the wrong place to do this! ***
    # This doesn't really work -- file names could still have chars that need to be escaped.
    $link_href =~ s/\s/%20/g;

    # Returns hash of the properties that were highlighted
    my $highlighted = $self->highlight_props( $props ) || {};

    my $trim_prop = $self->config('swishe_description_prop') || '';
    $props->{$trim_prop} ||= ''
        if $trim_prop;

    # HTML escape all properties that were not highlighted
    for my $prop (keys %$props) {
        next if  $highlighted->{$prop};

        # not highlighted, so escape
        html_escape( $props->{$prop} );

        if ( $prop eq $trim_prop ) {
            my $max = $self->config('swishe_max_chars') || 500;

            $props->{$trim_prop} = substr( $props->{$trim_prop}, 0, $max) . ' <b>...</b>'
                if length $props->{$trim_prop} > $max;
        }
    }

    $props->{percent} = ($props->{swishrank} / 1000) * 100;
    $props->{swishdocpath_href} = $link_href;  # backwards compatible
    $props->{link_property} = $link_href;  # backwards compatible

    # Push the result onto the list
    push @{$self->{_results}}, $props;
}


#=============================================================================


# This will call the highlighting module as needed.
# The highlighting module MUST html escape the property.
# returns a hash of properties highlighted


sub highlight_props {
    my ( $self, $props ) = @_;

    # make sure we have the config we need.
    my $highlight_settings = $self->config('swishe_highlight') || return;
    my $meta_to_prop = $self->config('swishe_highlight_meta_to_prop_map') || return;

    # Initialize highlight module ( could probably do this once per instance )
    # pass in the config highlight settings, and the swish-e headers as a hash.

    $self->{_highlight_object} ||= $highlight_settings->{package}->new( $highlight_settings, $self->{_headers} );
    my $highlight_object = $self->{_highlight_object} || return;

    # parse the query on first result

    my $parsed_words =  $self->header( 'parsed words' ) || die "Failed to find 'Parsed Words' in swishe headers";

    $self->{parsed_query} ||= ( SWISH::ParseQuery::parse_query( $parsed_words ) || return );


    my %highlighted;  # track which were highlighted to detect if need to trim the description


    # this is probably backwards -- might be better to loop through the %$props

    foreach my $meta (keys %{$self->{parsed_query}} )
    {
	my $phrases = $self->{parsed_query}->{$meta};

        next unless $meta_to_prop->{$meta};  # is it a prop defined to highlight?

        # loop through the properties for the metaname

        for ( @{ $meta_to_prop->{$meta} } )
	{
            if ( $props->{$_} )
	    {
		if (!$highlighted{$_})
		{
		    $highlighted{$_}++ if $highlight_object->highlight( \$props->{$_}, $phrases, $_ );
		}
	    }
        }
    }

    return \%highlighted;
}

#==================================================================
# Run swish-e by using the SWISH::API module
#

my %cached_handles;

sub run_library {
    my ( $self, @props ) = @_;

    my $indexes = $self->swishe_command('-f');

    print STDERR "swishe.cgi: running library thus no 'output' available -- try 'summary'\n"
        if ($self->{config}{swishe_debug} || 0);

    eval { require Time::HiRes };
    my $start_time = [Time::HiRes::gettimeofday()] unless $@;

    unless ( $cached_handles{$indexes} ) {

        my $swishe = SWISH::API->new( ref $indexes ? join(' ', @$indexes) : $indexes );
        if ( $swishe->Error ) {
            $self->errstr( join ': ', $swishe->ErrorString, $swishe->LastErrorMsg );
            delete $cached_handles{$indexes} if $swishe->CriticalError;
            return;
        }

        # read headers (currently only reads one set)
        my %headers;
        my $index = ($swishe->IndexNames)[0];

        for ( $swishe->HeaderNames ) {
            my @value = $swishe->HeaderValue( $index, $_ );
            my $x = @value;
            next unless @value;
            $headers{ lc($_) } = join ' ', @value;
        }

        $cached_handles{$indexes} = {
            swishe => $swishe,
            headers => \%headers,
        };
    }

    my $swishe = $cached_handles{$indexes}{swishe};

    my $headers = $cached_handles{$indexes}{headers};

    $self->{_headers} = $headers;

    my $search = $swishe->New_Search_Object;  # probably could cache this, too

    if ( my $limits = $self->swishe_command( 'limits' ) ) {
        $search->SetSearchLimit( @{$limits}{ qw/prop low high/ } );
    }

    if ( $swishe->Error ) {
        $self->errstr( join ': ', $swishe->ErrorString, $swishe->LastErrorMsg );
        delete $cached_handles{$indexes} if $swishe->CriticalError;
        return;
    }

    if ( my $sort = $self->swishe_command('-s') ) {
        $search->SetSort( ref $sort ? join( ' ', @$sort) : $sort );
    }

    my $search_time = [Time::HiRes::gettimeofday()] if $start_time;

    my $results = $search->execute( $self->swishe_command('-w') );

    $headers->{'search time'} = sprintf('%0.3f seconds', Time::HiRes::tv_interval( $search_time, [Time::HiRes::gettimeofday()] ))
        if $start_time;

    if ( $swishe->Error ) {
        $self->errstr( join ': ', $swishe->ErrorString, $swishe->LastErrorMsg );
        delete $cached_handles{$indexes} if $swishe->CriticalError;
        return;
    }

    # Add in results-related headers
    $headers->{'parsed words'} = join ' ', $results->ParsedWords( ($swishe->IndexNames)[0] );

    if ( ! $results->Hits ) {
        $self->errstr('no results');
        return;
    }
    $headers->{'number of hits'} = $results->Hits;

    # Get stopwords removed from each index (really need to track headers per index to be correct)

    for my $index ( $swishe->IndexNames ) {
        my @stopwords = $results->RemovedStopwords( $index );

        push @{$headers->{'removed stopwords'}}, @stopwords
            if @stopwords;
    }

    # Now fetch properties

    $results->seek_result( $self->swishe_command( '-b' ) - 1 );

    my $page_size = $self->swishe_command( '-m' );

    if ( $swishe->Error ) {
        $self->errstr( join ': ', $swishe->ErrorString, $swishe->LastErrorMsg );
        delete $cached_handles{$indexes} if $swishe->CriticalError;
        return;
    }

    my $hit_count = 0;

    $self->{_results} = [];
    while ( my $result = $results->next_result ) {
        my %props;

        for my $prop ( @props ) {
            # Note, we use ResultPropertyStr instead since this is a
	    # general purpose
            # script (it converts dates to a string, for example).
            # $result->Property is a faster method and does not convert
	    # dates and numbers to strings.
            #my $value = $result->Property( $prop );
            my $value = $result->ResultPropertyStr( $prop );
            next unless $value;  # ??

            $props{$prop} = $value;
        }
        $hit_count++;
	$props{count} = $hit_count;

        $self->add_result_to_list( \%props );

        last unless --$page_size;
    }

    $headers->{'run time'} = sprintf('%0.3f seconds', Time::HiRes::tv_interval( $start_time, [Time::HiRes::gettimeofday()] ))
        if $start_time;

    $self->{hits} = $hit_count;
} # run_library



#==================================================================
# Run swish-e by forking
#

use Symbol;

sub real_fork {
    my ( $conf, $self ) = @_;


    # Run swishe
    my $fh = gensym;
    my $pid = open( $fh, '-|' );

    die "Failed to fork: $!\n" unless defined $pid;


    if ( !$pid ) {  # in child
        unless ( exec $self->{prog},  $self->swishe_command_array ) {
            warn "Child process Failed to exec '$self->{prog}' Error: $!";
            print "Failed to exec Swish";  # send this message to parent.
            exit;
        }
    } else {
        $self->{pid} = $pid;
    }

    return $fh;
}

sub generate_view{
    my $self = shift;

    warningsToBrowser(1); # set warnings as comments 
    my $query = $self->{query_simple};
    my $meta_select_list    = $self->get_meta_name_limits();
    my $sorts               = $self->get_sort_select_list();
    my $select_index        = $self->get_index_select_list();
    my $limit_select        = $self->get_limit_select();
    my $date_ranges_select  = $self->get_date_ranges;
    my $pages       = $self->navigation('pages');
    my $prev        = $self->navigation('prev');
    my $prev_count  = $self->navigation('prev_count');
    my $next        = $self->navigation('next');
    my $next_count  = $self->navigation('next_count');
    my $hits        = $self->navigation('hits');
    my $from        = $self->navigation('from');
    my $to          = $self->navigation('to');
    my $query_href = $self->{query_href};
    my $links = '';
    $links .= qq[ <a href="$query_href&amp;start=$prev">Previous $prev_count</a> ]
        if $prev_count;
    $links .= $pages if $pages;
    $links .= qq[ <a href="$query_href&amp;start=$next">Next $next_count</a>]
        if $next_count;
    $links = "Page:&nbsp;$links" if $links;

    my $run_time    = $self->navigation('run_time');
    my $search_time = $self->navigation('search_time');
    my $stopwords = $self->header('removed stopwords');

    my $template;
    eval {
	$template=IkiWiki::template("swishe_results.tmpl",
	    blind_cache => 1);
    };
    if ($@) {
	croak "failed to process template swishe_results.tmpl: $@";
    }
    if (! $template) {
	croak sprintf("%s not found", "/templates/swishe_results.tmpl");
    }

    $template->param(searchaction => IkiWiki::cgiurl());
    $template->param(ERRORMSG=>$self->errstr());
    $template->param(TITLE=>$IkiWiki::config{swishe_title});
    $template->param(QUERY=>$query);
    $template->param(SEARCH_TIME=>$search_time);
    $template->param(RUN_TIME=>$run_time);
    $template->param(HITS=>$hits);
    $template->param(FROM=>$from);
    $template->param(TO=>$to);
    $template->param(REMOVED_STOPWORDS=>($stopwords
	    ? join(' ', @$stopwords) : ''));
    $template->param(META_SELECT=>$meta_select_list);
    $template->param(SORTS=>$sorts);
    $template->param(LIMIT_SELECT=>$limit_select);
    $template->param(DATE_RANGES=>$date_ranges_select);
    $template->param(SELECT_INDEX=>$select_index);
    $template->param(SEARCH_NAV=>$links);

    $template->param(RESULTS=>$self->results());

    my $content = $template->output;

    my $page = $IkiWiki::config{swishe_page};
    my $ptmpl = IkiWiki::template('page.tmpl', blind_cache=>1);
    $ptmpl->param(
		  title => $IkiWiki::config{swishe_title},
		  wikiname => $IkiWiki::config{wikiname},
		  content => $content,
		  html5 => $IkiWiki::config{html5},
		  dynamic => 1,
		 );

    IkiWiki::run_hooks(pagetemplate => sub {
		       shift->(page => $page,
			       destpage => $page,
			       dynamic=>1,
			       template => $ptmpl);
		       });

    $content=$ptmpl->output;

    IkiWiki::run_hooks(format => sub {
		       $content=shift->(
				    page => $page,
				    content => $content,
				    dynamic=>1,
				   );
		       });
    return $content;
} # generate_view

sub get_meta_name_limits {
    my $self = shift;

    my $metanames = $IkiWiki::config{'swishe_metanames'};
    return '' unless $metanames;

    my $name_labels = $IkiWiki::config{'swishe_name_labels'};

    return join "\n",
        'Limit search to:',
        CGI::radio_group(
            -name   =>'metaname',
            -values => $metanames,
            -default=>$metanames->[0],
            -labels =>$name_labels
        ),
        '<br>';
}

sub get_sort_select_list {
    my $self = shift;

    my $sort_metas = $IkiWiki::config{'swishe_sorts'};
    return '' unless $sort_metas;
    
    my $name_labels = $IkiWiki::config{'swishe_name_labels'};

    return join "\n",
        'Sort by:',
        CGI::popup_menu(
            -name   =>'sort',
            -values => $sort_metas,
            -default=>$sort_metas->[0],
            -labels =>$name_labels
        ),
        CGI::checkbox(
            -name   => 'reverse',
            -label  => 'Reverse Sort'
        );
}

sub get_index_select_list {
    my $self = shift;

    my $indexes = $IkiWiki::config{'swishe_index'};
    return '' unless ref $indexes eq 'ARRAY';

    my $select_config = $IkiWiki::config{'swishe_select_indexes'};
    return '' unless $select_config && ref $select_config eq 'HASH';

    # Should return a warning, as this might be a likely mistake
    # This jumps through hoops so that real index file name is not exposed
    
    return '' unless exists $select_config->{labels}
              && ref $select_config->{labels} eq 'ARRAY'
              && @$indexes == @{$select_config->{labels}};

    my @labels = @{$select_config->{labels}};
    my %map;

    for ( 0..$#labels ) {
        $map{$_} = $labels[$_];
    }

    my $method = $select_config->{method} || 'checkbox_group';
    my @cols = $select_config->{columns} ? ('-columns', $select_config->{columns}) : ();

    my %options = (
        -name   => 'si',
        -values => [0..$#labels],
        -default=> 0,
        -labels => \%map,
	@cols
    );

    return join "\n",
        ( $select_config->{description} || 'Select: '),
	($method eq 'popup_menu'
	    ? CGI::popup_menu(%options)
	    : ($method eq 'scrolling_list'
		? CGI::scrolling_list(%options)
		: ($method eq 'radio_group'
		    ? CGI::radio_group(%options)
		    : CGI::checkbox_group(%options)
		)
	    )
	);
}


sub get_limit_select {
    my $self = shift;

    my $limit = $IkiWiki::config{'swishe_select_by_meta'};
    return '' unless ref $limit eq 'HASH';

    my $method = $limit->{method} || 'checkbox_group';

    my $values = $IkiWiki::config{'swishe_select_by_meta_values'};
    my $labels = $IkiWiki::config{'swishe_select_by_meta_labels'};
    my %options = (
        -name   => 'sbm',
        -values => $values,
        -labels => $labels || {},
    );

    $options{-columns} = $limit->{columns} if $limit->{columns};

    return join "\n",
        ( $limit->{description} || 'Select: '),
	($method eq 'popup_menu'
	    ? CGI::popup_menu(%options)
	    : ($method eq 'scrolling_list'
		? CGI::scrolling_list(%options)
		: ($method eq 'radio_group'
		    ? CGI::radio_group(%options)
		    : CGI::checkbox_group(%options)
		)
	    )
	);
}
#==============================================================================
#   Windows work around
#   from perldoc perlfok -- na, that doesn't work.  Try IPC::Open2
#
sub windows_fork {
    my ( $conf, $self ) = @_;


    require IPC::Open2;
    my ( $rdrfh, $wtrfh );

    # Ok, I'll say it.  Windows sucks.
    my @command = map { s/"/\\"/g; qq["$_"] }  $self->{prog}, $self->swishe_command_array;
    my $pid = IPC::Open2::open2($rdrfh, $wtrfh, @command );


    $self->{pid} = $pid;

    return $rdrfh;
}


1
