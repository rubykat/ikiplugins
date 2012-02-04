#!/usr/bin/perl
# Report on a SQLite database
package IkiWiki::Plugin::sqlreport;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::sqlreport - report on a SQLite database

=head1 VERSION

This describes version B<1.20120204> of IkiWiki::Plugin::sqlreport

=cut

our $VERSION = '1.20120204';

=head1 PREREQUISITES

    IkiWiki
    DBI
    DBD::SQLite
    Text::NeatTemplate

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2012 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use DBI;
use POSIX;
use YAML;
use Text::NeatTemplate;
use SQLite::Work;

my %Databases = ();

sub import {
    hook(type => "getsetup", id => "sqlreport",  call => \&getsetup);
    hook(type => "checkconfig", id => "sqlreport", call => \&checkconfig);
    hook(type => "preprocess", id => "sqlreport", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "misc",
		},
		sqlreport_databases => {
			type => "hash",
			example => "sqlreport_databases => { foo => '/home/fred/mydb.sqlite' }",
			description => "mapping from database names to files",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    if (!exists $config{sqlreport_databases})
    {
	error gettext("sqlreport: sqlreport_databases undefined");
    }
    # check and open the databases
    while (my ($alias, $file) = each %{$config{sqlreport_databases}})
    {
	if (!-r $file)
	{
	    error(gettext("sqlreport: cannot read database file $file"));
	}
	my $rep = SQLite::Work::IkiWiki->new(database=>$file);
	if (!$rep or !$rep->do_connect())
	{
	    error(gettext("Can't connect to $file: $DBI::errstr"));
	}
	$Databases{$alias} = $rep;
    }
}

sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};
    delete $params{page};
    foreach my $p (qw(database table where))
    {
	if (!exists $params{$p})
	{
	    error gettext("sqlreport: missing $p parameter");
	}
    }
    if (!exists $config{sqlreport_databases}->{$params{database}})
    {
	error(gettext(sprintf('sqlreport: database %s does not exist',
		$params{database})));
    }
    my $out = '';

    $out = $Databases{$params{database}}->do_report(%params);
    return $out;
} # preprocess

package SQLite::Work::IkiWiki;
use SQLite::Work;
use Text::NeatTemplate;
our @ISA = qw(SQLite::Work);

sub new {
    my $class = shift;
    my %parameters = (@_);
    my $self = SQLite::Work->new(%parameters);

    $self->{report_template} = '<!--sqlr_contents-->'
	if !defined $parameters{report_template};
    bless ($self, ref ($class) || $class);
} # new

=head2 print_select

RETURN a selection result.

=cut
sub print_select {
    my $self = shift;
    my $sth = shift;
    my $sth2 = shift;
    my %args = (
	table=>'',
	title=>'',
	command=>'Search',
	prev_file=>'',
	prev_label=>'Prev',
	next_file=>'',
	next_label=>'Next',
	prev_next_template=>'',
	@_
    );
    my @columns = @{$args{columns}};
    my @sort_by = @{$args{sort_by}};
    my $table = $args{table};
    my $page = $args{page};

    # read the template
    my $template = $self->get_template($self->{report_template});
    $self->{report_template} = $template;

    my $num_pages = ($args{limit} ? ceil($args{total} / $args{limit}) : 1);
    # generate the HTML table
    my $count = 0;
    my $res_tab = '';
    ($count, $res_tab) = $self->format_report($sth,
	%args,
	table=>$table,
	table2=>$args{table2},
	columns=>\@columns,
	sort_by=>\@sort_by,
	num_pages=>$num_pages,
	);
    my $main_title = ($args{title} ? $args{title}
	: "$table $args{command} result");
    my $title = ($args{limit} ? "$main_title ($page)"
	: $main_title);
    # fix up random apersands
    if ($title =~ / & /)
    {
	$title =~ s/ & / &amp; /g;
    }
    my @result = ();
    push @result, $res_tab;
    push @result, "<p>$count rows displayed of $args{total}.</p>\n"
	if ($args{report_style} ne 'bare'
	    and $args{report_style} ne 'compact');
    if ($args{limit} and $args{report_style} eq 'full')
    {
	push @result, "<p>Page $page of $num_pages.</p>\n"
    }
    if (defined $sth2)
    {
	my @cols2 = $self->get_colnames($args{table2});
	my $count2;
	my $tab2;
	($count2, $tab2) = $self->format_report($sth2,
						%args,
						table=>$args{table2},
						columns=>\@cols2,
						sort_by=>\@cols2,
						headers=>[],
						groups=>[],
						row_template=>'',
						num_pages=>0,
					       );
	if ($count2)
	{
	    push @result,<<EOT;
<h2>$args{table2}</h2>
$tab2
<p>$count2 rows displayed from $args{table2}.</p>
EOT
	}
    }

    # prepend the message
    unshift @result, "<p><i>$self->{message}</i></p>\n", if $self->{message};

    # append the prev-next links, if any
    if ($args{prev_file} or $args{next_file})
    {
	my $prev_label = $args{prev_label};
	my $next_label = $args{next_label};
	my %pn_hash = (
		       prev_file => $args{prev_file},
		       prev_label => $prev_label,
		       next_file => $args{next_file},
		       next_label => $next_label,
		      );
	my $pn_template = ($args{prev_next_template}
			   ? $args{prev_next_template}
			   : '<hr/>
			   <p>{?prev_file <a href="[$prev_file]">[$prev_label]</a>}
			   {?next_file <a href="[$next_file]">[$next_label]</a>}
			   </p>
			   '
			  );
	my $pn_templ = $self->get_template($pn_template);
	my $pn_str = $self->{_tobj}->fill_in(data_hash=>\%pn_hash,
					     template=>$pn_templ);
	push @result, $pn_str;
    }

    my $contents = join('', @result);
    my $out = $template;
    $out =~ s/<!--sqlr_title-->/$title/g;
    $out =~ s/<!--sqlr_contents-->/$contents/g;

    # RETURN the result
    return $out;
} # print_select

=head2 build_where_conditions

If "where" is not a hash. treat it like a query.

Otherwise do the default of the superclass.

=cut
sub build_where_conditions {
    my $self = shift;
    my %args = @_;

    if (ref $args{where} eq 'HASH')
    {
	return $self->SUPER::build_where_conditions(%args);
    }
    my @where = ();
    $args{where} =~ s/;//g; # crude prevention of injection
    $where[0] = $args{where};

    return @where;
} # build_where_conditions

=head2 do_report

Do a report, pre-processing the arguments a bit.

=cut
sub do_report {
    my $self = shift;
    my %args = (
	command=>'Select',
	limit=>0,
	page=>1,
	headers=>'',
	groups=>'',
	sort_by=>'',
	sort_reversed=>{},
	not_where=>{},
	where=>{},
	show=>'',
	layout=>'table',
	row_template=>'',
	outfile=>'',
	report_style=>'full',
	title=>'',
	prev_file=>'',
	next_file=>'',
	@_
    );
    my $table = $args{table};
    my $command = $args{command};
    my @headers = (ref $args{headers} ? @{$args{headers}}
	: split(/|/, $args{headers}));
    my @groups = (ref $args{groups} ? @{$args{groups}}
	: split(/|/, $args{groups}));
    my @sort_by = (ref $args{sort_by} ? @{$args{sort_by}}
	: split(' ', $args{sort_by}));


    my @columns = (ref $args{show}
	? @{$args{show}}
	: ($args{show}
	    ? split(' ', $args{show})
	    : $self->get_colnames($table)));

    my $total = $self->get_total_matching(%args);

    my ($sth1, $sth2) = $self->make_selections(%args,
	show=>\@columns,
	sort_by=>\@sort_by,
	total=>$total);
    $self->print_select($sth1,
	$sth2,
	%args,
	show=>\@columns,
	sort_by=>\@sort_by,
	message=>$self->{message},
	command=>$command,
	total=>$total,
	columns=>\@columns,
	headers=>\@headers,
	groups=>\@groups,
	);
} # do_report
1
