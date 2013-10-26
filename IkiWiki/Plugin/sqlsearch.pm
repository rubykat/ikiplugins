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
    delete $params{page};
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
    my $out = '';

    $out = $Databases{$params{database}}->make_search_form($params{table}, %params);

    if ($params{ltemplate}
        and $out)
    {
        my $out2 = $params{ltemplate};
        $out2 =~ s/CONTENTS/$out/g;
        $out = $out2;
    }
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
        my $database = $cgi->param('database');
        my $table = $cgi->param('Table');
        my $results = $Databases{$database}->do_select($table);

        # show the results
	print $cgi->header;
	print $results;
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
    my $form = $self->search_form($table,
	command=>$args{command});
    my $title = $args{command} . ' ' . $table;

    $form = "<p><i>$self->{message}</i></p>\n" . $form if $self->{message};

    my $out = $template;
    $out =~ s/<!--sqlr_title-->/$title/g;
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

    my @columns = $self->get_colnames($table);
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
</table>
</td><td>
<p>Select the order of columns to display;
and which columns <em>not</em> to display.</p>
<table border="0">
EOT
    for (my $i = 0; $i < @columns; $i++) {
	my $col = $columns[$i];

	$out_str .= "<tr><td>";
	$out_str .= "<select name='${show_label}'>\n";
	$out_str .= "<option value=''>-- not displayed --</option>\n";
	foreach my $fname (@columns)
	{
	    if ($fname eq $col)
	    {
		$out_str .= "<option selected='true' value='${fname}'>${fname}</option>\n";
	    }
	    else
	    {
		$out_str .= "<option value='${fname}'>${fname}</option>\n";
	    }
	}
	$out_str .= "</select>";
	$out_str .= "</td>";
	$out_str .= "</tr>\n";
}
    $out_str .=<<EOT;
</table></td><td>
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
EOT
    if ($command eq 'Search')
    {
	$out_str .=<<EOT;
<p><strong>Report Layout:</strong><select name="ReportLayout">
<option value="table">table</option>
<option value="para">paragraph</option>
<option value="list">list</option>
</select>
</p>
EOT
    }

    $out_str .=<<EOT;
<p><strong>Report Style:</strong><select name="ReportStyle">
<option value="full">Full</option>
<option value="medium">Medium</option>
<option value="compact">Compact</option>
<option value="bare">Bare</option>
</select>
</p>
EOT
    $out_str .=<<EOT;
</td></tr></table>
<table border="0">
<tr><td>
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
</td><td>
EOT
    if ($command eq 'Search')
    {
	$out_str .=<<EOT;
<p><strong>Headers:</strong>
Indicate which columns you wish to be in headers by giving
the columns in template form; for example:<br/>
{\$Col1} {\$Col2}<br/>
means that the header contains columns <em>Col1</em> and <em>Col2</em>.
<br/>
EOT
	for (my $i=1; $i <= $self->{max_headers}; $i++)
	{
	    $out_str .=<<EOT
<strong>Header $i</strong>
<input type="text" name="$headers_label" size="60"/><br/>
EOT
	}
	$out_str .= "</p>\n";
    }

    $out_str .=<<EOT;
</td></tr>
</table>
<p><strong><input type="submit" name="$command" value="$command"/> <input type="reset"/></strong>
EOT
    if ($command eq 'Edit')
    {
	$out_str .=<<EOT;
<input type="submit" name="Add_Row" value="Add Row"/>
EOT
    }
    $out_str .=<<EOT;
</p>
</form>
EOT
    return $out_str;
} # search_form


1
