#!/usr/bin/perl
# Search a SQLite database
package IkiWiki::Plugin::sqlsearch;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::sqlsearch - search a SQLite database

=head1 VERSION

This describes version B<0.20131024> of IkiWiki::Plugin::sqlsearch

=cut

our $VERSION = '0.20131024';

=head1 PREREQUISITES

    IkiWiki
    SQLite::Work
    Text::NeatTemplate

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2013 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use DBI;
use POSIX;
use YAML;
use Text::NeatTemplate;
use SQLite::Work;
use SQLite::Work::CGI;

my %Databases = ();
my $DBs_Connected = 0;

sub import {
    hook(type => "getsetup", id => "sqlsearch",  call => \&getsetup);
    hook(type => "checkconfig", id => "sqlsearch", call => \&checkconfig);
    hook(type => "preprocess", id => "sqlsearch", call => \&preprocess);
    hook(type => "change", id => "sqlsearch", call => \&hang_up);
    hook(type => "cgi", id => "sqlsearch", call => \&cgi);
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
	error gettext("sqlsearch: sqlreport_databases undefined");
    }
    # check and open the databases
    while (my ($alias, $file) = each %{$config{sqlreport_databases}})
    {
	if (!-r $file)
	{
	    debug(gettext("sqlsearch: cannot read database file $file"));
	    delete $config{sqlreport_databases}->{$alias};
	}
	else
	{
	    my $rep = SQLite::Work::CGI::IkiWiki->new(database=>$file,
                        alias   => $alias,
	                config    => \$IkiWiki::config,
            );
	    if (!$rep or !$rep->do_connect())
	    {
		error(gettext("Can't connect to $file: $DBI::errstr"));
	    }
            $rep->{dbh}->{sqlite_unicode} = 1;
            $Databases{$alias} = $rep;
	    $DBs_Connected = 1;
	}
    }
}

sub preprocess (@) {
    my %params=@_;

    my $page = $params{page};
    foreach my $p (qw(database table where))
    {
        if (!exists $params{$p})
        {
            error gettext("sqlsearch: missing $p parameter");
        }
    }
    if (!exists $config{sqlreport_databases}->{$params{database}})
    {
        error(gettext(sprintf('sqlsearch: database %s does not exist',
                              $params{database})));
    }

    # remember the parameters
    foreach my $key (keys %params)
    {
        if ($key =~ /^(page|destpage|preview|_raw)$/) # skip non-parameters
        {
            next;
        }
        my $value = $params{$key};
        $pagestate{$params{page}}{sqlsearch}{$key} = $value;
    }

    my $out = '';

    $out = $Databases{$params{database}}->make_search_form($params{table}, page=>$page, %params);

    return $out;
} # preprocess

sub hang_up {
    my $rendered = shift;

    # Hack for disconnecting from the databases

    if ($DBs_Connected)
    {
	while (my ($alias, $rep) = each %Databases)
	{
	    $rep->do_disconnect();
	}
	$DBs_Connected = 0;
    }
} # hang_up 

sub cgi ($) {
    my $cgi=shift;

    if (defined $cgi->param('database')) {
        # process the query
        IkiWiki::loadindex();
        my $database = $cgi->param('database');
        my $table = $cgi->param('Table');
        my $form_page = $cgi->param('form_page');
        my $results = $Databases{$database}->do_select($table);

        # show the results
	print $cgi->header;
	print IkiWiki::cgitemplate(undef, $form_page, $results);

	exit;
    }
}

# =================================================================
package SQLite::Work::CGI::IkiWiki;
use SQLite::Work;
use SQLite::Work::CGI;
use POSIX;
our @ISA = qw(SQLite::Work::CGI);

sub new {
    my $class = shift;
    my %parameters = (@_);
    my $self = SQLite::Work::CGI->new(%parameters);

    $self->{where_prefix} ||= 'where_';
    bless ($self, ref ($class) || $class);
} # new

=head2 make_search_form

Create the search form for the given table.

my $form = $obj->make_search_form($table, %args);

=cut
sub make_search_form {
    my $self = shift;
    my $table = shift;
    my %args = (
	command=>'Search',
	@_
    );

    # read the template
    my $template;
    if ($self->{report_template} !~ /\n/
	&& -r $self->{report_template})
    {
	local $/ = undef;
	my $fh;
	open($fh, $self->{report_template})
	    or die "Could not open ", $self->{report_template};
	$template = <$fh>;
	close($fh);
    }
    else
    {
	$template = $self->{report_template};
    }
    # generate the search form
    my $form = $self->search_form($table, %args);

    $form = "<p><i>$self->{message}</i></p>\n" . $form if $self->{message};

    my $out = $template;
    $out =~ s/<!--sqlr_contents-->/$form/g;
    return $out;

} # make_search_form

=head2 search_form

Construct a search-a-table form

=cut
sub search_form {
    my $self = shift;
    my $table = shift;
    my %args = (
	command=>'Search',
	@_
    );

    my @columns = (ref $args{fields}
	? @{$args{fields}}
	: ($args{fields}
	    ? split(' ', $args{fields})
	    : $self->get_colnames($table)));
    my $form_page = $args{page};
    my $command = $args{command};
    my $where_prefix = $self->{where_prefix};
    my $not_prefix = $self->{not_prefix};
    my $show_label = $self->{show_label};
    my $sort_label = $self->{sort_label};
    my $sort_reversed_prefix = $self->{sort_reversed_prefix};
    my $headers_label = $self->{headers_label};

    my $action = IkiWiki::cgiurl();
    my $out_str =<<EOT;
<form action="$action" method="get">
<p>
<strong><input type="submit" name="$command" value="$command"/> <input type="reset"/></strong>
EOT
    $out_str .=<<EOT;
<input type="hidden" name="database" value="$self->{alias}"/>
<input type="hidden" name="form_page" value="${form_page}"/>
<input type="hidden" name="Table" value="$table"/>
</p>
<table border="0">
<tr><td>
<p>Match by column: use <b>*</b> as a wildcard match,
and the <b>?</b> character to match
any <em>single</em> character.
Click on the "NOT" checkbox to negate a match.
</p>
<table border="1" class="plain">
<tr>
<td>Columns</td>
<td>Match</td>
<td>&nbsp;</td>
</tr>
EOT
    for (my $i = 0; $i < @columns; $i++) {
	my $col = $columns[$i];
	my $wcol_label = "${where_prefix}${col}";
	my $ncol_label = "${not_prefix}${col}";

	$out_str .= "<tr><td>";
	$out_str .= "<strong>$col</strong>";
	$out_str .= "</td>\n<td>";
	$out_str .= "<input type='text' name='$wcol_label'/>";
	$out_str .= "</td>\n<td>";
	$out_str .= "<input type='checkbox' name='$ncol_label'>NOT</input>";
	$out_str .= "</td>";
	$out_str .= "</tr>\n";
}
    $out_str .=<<EOT;
</table> <!--end of columns -->
EOT
    for (my $i = 0; $i < @columns; $i++) {
	my $col = $columns[$i];

        $out_str .=<<EOT
<input type="hidden" name="${show_label}" value="${col}"/>
EOT
    }
$out_str .=<<EOT;
</td><td>
EOT
    $out_str .=<<EOT;
<p><strong>Num Results:</strong><select name="Limit">
<option value="0">All</option>
<option value="1">1</option>
<option value="10">10</option>
<option value="20">20</option>
<option value="50">50</option>
<option value="100">100</option>
</select>
</p>
<p><strong>Page:</strong>
<input type="text" name="Page" value="1"/>
</p>
<p><strong>Sort by:</strong> To set the sort order, select the column names.
To sort that column in reverse order, click on the <strong>Reverse</strong>
checkbox.
</p>
<table border="0">
EOT
    my $num_sort_fields = ($self->{max_sort_fields} < @columns
	? $self->{max_sort_fields} : @columns);
    for (my $i=0; $i < $num_sort_fields; $i++)
    {
	my $col = $columns[$i];
	$out_str .= "<tr><td>";
	$out_str .= "<select name='${sort_label}'>\n";
	$out_str .= "<option value=''>--choose a sort column--</option>\n";
	foreach my $fname (@columns)
	{
	    $out_str .= "<option value='${fname}'>${fname}</option>\n";
	}
	$out_str .= "</select>";
	$out_str .= "</td>";
	$out_str .= "<td>Reverse <input type='checkbox' name='${sort_reversed_prefix}${i}' value='1'/>";
	$out_str .= "</td>\n";
	$out_str .= "</tr>";
    }

    $out_str .=<<EOT;
</table>
</td></tr></table>
<p><strong><input type="submit" name="$command" value="$command"/> <input type="reset"/></strong>
EOT
    $out_str .=<<EOT;
</p>
</form>
EOT
    return $out_str;
} # search_form

=head2 make_buttons

Make the buttons for the forms.

=cut
sub make_buttons {
    my $self = shift;
    my %args = (
	table=>'',
	command=>'Search',
	@_
    );
    my $table = $args{table};
    my $table2 = $args{table2};
    my $page = $args{page};
    my $limit = $args{limit};
    my $total = $args{total};
    my $command = $args{command};

    my $num_pages = ($limit ? ceil($total / $limit) : 0);

    my $form_page = $args{form_page};
    my $pageurl = IkiWiki::urlto($form_page);

    my $url = $self->{cgi}->url();
    my @out = ();
    push @out,<<EOT;
<table>
<tr><td>
<form action="$url" method="get">
<input type="hidden" name="database" value="$self->{alias}"/>
<input type="hidden" name="Table" value="$table"/>
<a href="$pageurl">Back to $form_page</a>
EOT
    push @out,<<EOT;
</form></td>
EOT

    if ($args{limit})
    {
	# reproduce the query ops, with a different page
	# first
	push @out, "<td>";
	push @out, $self->make_page_button(command=>$command,
	    the_page=>1,
	    page_label=>' |&lt; ');
	push @out, "</td>\n";
	# prev
	push @out, "<td>";
	push @out, $self->make_page_button(command=>$command,
	    the_page=>$page - 1,
	    page_label=>' &lt; ');
	push @out, "</td>\n";
	# next
	push @out, "<td>";
	push @out, $self->make_page_button(command=>$command,
	    the_page=>$page + 1,
	    page_label=>' &gt; ');
	push @out, "</td>\n";
	# last
	push @out, "<td>";
	push @out, $self->make_page_button(command=>$command,
	    the_page=>$num_pages,
	    page_label=>' &gt;| ');
	push @out, "</td>\n";
	push @out, "</tr></table>\n";
    }
    else # no pages
    {
	push @out,<<EOT;
</tr></table>
EOT
    }

    return join('', @out);
} # make_buttons

=head2 do_select

$obj->do_select($table,
    command=>'Search');

Select data from a table in the database.
Uses CGI to get most of the parameters.

=cut
sub do_select {
    my $self = shift;
    my $table = shift;
    my %args = (
	command=>'Search',
	outfile=>'',
	@_
    );
    my $command = $args{command};

    my $where_prefix = $self->{where_prefix};
    my $not_prefix = $self->{not_prefix};
    my $show_label = $self->{show_label};
    my $sort_label = $self->{sort_label};
    my $sort_reversed_prefix = $self->{sort_reversed_prefix};
    my @columns = ();
    my %where = ();
    my %not_where = ();
    my @sort_by = ();
    my @sort_r = ();
    my %sort_reverse = ();
    my $form_page = $self->{cgi}->param('form_page');


    my $limit = $self->{cgi}->param('Limit');
    $limit = 0 if !$limit;
    my $page = $self->{cgi}->param('Page');
    $page = 1 if !$page;
    my $row_id_name = $self->get_id_colname($table);

    my $pre_where = $IkiWiki::pagestate{$form_page}{sqlsearch}{'where'};
    my $pre_sort = $IkiWiki::pagestate{$form_page}{sqlsearch}{'sort_by'};
    my $layout = $IkiWiki::pagestate{$form_page}{sqlsearch}{'report_layout'};
    my $report_style = $IkiWiki::pagestate{$form_page}{sqlsearch}{'report_style'};
    my %predefined_args = ();
    foreach my $key (keys %{$IkiWiki::pagestate{$form_page}{sqlsearch}})
    {
        if ($key !~ /^(page|where|report_layout|report_style|database|table|sort_by|show)$/)
        {
            $predefined_args{$key} =
                $IkiWiki::pagestate{$form_page}{sqlsearch}{$key};
        }
    }

    # build up the data
    foreach my $pfield ($self->{cgi}->param())
    {
	my $pval = $self->{cgi}->param($pfield);
	if ($pfield eq $show_label)
	{
	    my (@show) = $self->{cgi}->param($pfield);
	    foreach my $scol (@show)
	    {
		# only show non-empty values!
		if ($scol)
		{
		    push @columns, $scol;
		}
	    }
	}
	elsif ($pfield =~ /^${where_prefix}(.*)/o)
	{
	    my $colname = $1;
	    if ($pval)
	    {
		my $not_where_field = "${not_prefix}${colname}";
		$pval =~ m#([^`]*)#;
		my $where_val = $1;
		$where_val =~ s/\s$//;
		$where_val =~ s/^\s//;
		if ($where_val)
		{
		    $where{$colname} = $where_val;
		    if ($self->{cgi}->param($not_where_field))
		    {
			$not_where{$colname} = 1;
		    }
		}
	    }
	}
	elsif ($pfield eq $sort_label)
	{
	    my (@vals) = $self->{cgi}->param($pfield);
	    foreach my $val (@vals)
	    {
		# only non-empty values!
		if ($val)
		{
		    push @sort_by, $val;
		}
	    }
	}
	elsif ($pfield =~ /^${sort_reversed_prefix}(.*)/o)
	{
	    my $ind = $1;
	    $sort_r[$ind] = ($pval ? 1 : 0);
	}
    }
    @columns = $self->get_colnames($table) if !@columns;
    if (@sort_by)
    {
	for (my $i=0; $i < @sort_r; $i++)
	{
	    if ($sort_r[$i])
	    {
		$sort_reverse{$sort_by[$i]} = 1;
	    }
	}
    }
    if ($pre_sort)
    {
        my @pre_sort = split(' ', $pre_sort);
        if (@sort_by)
        {
            unshift @sort_by, @pre_sort;
        }
        else
        {
            @sort_by = @pre_sort;
        }
    }

    $self->do_report(
        %predefined_args,
	table=>$table,
	table2=>($self->{cgi}->param('Table2')
		 ? $self->{cgi}->param('Table2') : ''),
	command=>$command,
	where=>\%where,
	not_where=>\%not_where,
	sort_by=>\@sort_by,
	sort_reversed=>\%sort_reverse,
	show=>\@columns,
	limit=>$limit,
	page=>$page,
	report_style=>($report_style ? $report_style : 'full'),
	layout=>($layout ? $layout : 'para'),
	outfile=>$args{outfile},
        form_page=>$form_page,
        pre_where=>$pre_where,
    );

} # do_select

=head2 build_where_conditions

If "where" is not a hash. treat it like a query.

Otherwise do the default of the superclass.

=cut
sub build_where_conditions {
    my $self = shift;
    my %args = @_;

    my @where = ();
    if (ref $args{where} eq 'HASH')
    {
	@where = $self->SUPER::build_where_conditions(%args);
    }
    else
    {
        $args{where} =~ s/;//g; # crude prevention of injection
        $where[0] = $args{where};
    }
    if ($args{pre_where})
    {
        push @where, $args{pre_where};
    }

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
	not_where=>{},
        pre_where=>'',
	where=>{},
	show=>'',
	layout=>'table',
	row_template=>'',
	outfile=>'',
	report_style=>'full',
	title=>'',
	prev_file=>'',
	next_file=>'',
        report_class=>'report',
	@_
    );
    my $table = $args{table};
    my $command = $args{command};
    my $report_class = $args{report_class};
    my @headers = (ref $args{headers} ? @{$args{headers}}
	: split(/\|/, $args{headers}));
    my @groups = (ref $args{groups} ? @{$args{groups}}
	: split(/\|/, $args{groups}));
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
    my $out = $self->print_select($sth1,
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
        title=>"Search result",
	);
    return $out;
} # do_report

=head2 print_select

Print a selection result.

=cut
sub print_select {
    my $self = shift;
    my $sth = shift;
    my $sth2 = shift;
    my %args = (
	table=>'',
	command=>'Search',
	@_
    );
    my @columns = @{$args{columns}};
    my @sort_by = @{$args{sort_by}};
    my $table = $args{table};
    my $page = $args{page};

    # read the template
    my $template;
    if ($self->{report_template} !~ /\n/
	&& -r $self->{report_template})
    {
	local $/ = undef;
	my $fh;
	open($fh, $self->{report_template})
	    or die "Could not open ", $self->{report_template};
	$template = <$fh>;
	close($fh);
    }
    else
    {
	$template = $self->{report_template};
    }
    # generate the HTML table
    my $count = 0;
    my $res_tab = '';
    ($count, $res_tab) = $self->format_report($sth,
					      %args,
					      table=>$table,
					      table2=>$args{table2},
					      columns=>\@columns,
					      sort_by=>\@sort_by,
					     );
    my $buttons = $self->make_buttons(%args);
    my $main_title = ($args{title} ? $args{title}
	: "$table $args{command} result");
    my $title = ($args{limit} ? "$main_title ($page)"
	: $main_title);
    my $res_info = '';
    $res_info .= "<p>$count rows displayed of $args{total}.</p>\n"
	if ($args{report_style} ne 'bare'
	    and $args{report_style} ne 'compact');
    if ($args{limit} and $args{report_style} eq 'full')
    {
	my $num_pages = ceil($args{total} / $args{limit});
	$res_info .= "<p>Page $page of $num_pages.</p>\n";
    }
    if (@sort_by)
    {
        $res_info .= "<p>Sort by: " . join(', ', @sort_by) . "</p>\n";
    }

    my @result = ();
    push @result, $buttons if ($args{report_style} ne 'bare');
    push @result, $res_info;
    push @result, $res_tab;
    push @result, $res_info;
    push @result, $buttons if ($args{report_style} ne 'bare');

    # prepend the query and message
    unshift @result, "<p>", join(' AND ', $self->build_where_conditions(%args)), "</p>\n";
    unshift @result, "<p>$args{query}</p>\n" if ($args{debug});
    unshift @result, "<p><i>$self->{message}</i></p>\n", if $self->{message};

    my $contents = join('', @result);
    my $out = $template;
    $out =~ s/<!--sqlr_title-->/$title/g;
    $out =~ s/<!--sqlr_contents-->/$contents/g;
    return $out;

} # print_select


1
