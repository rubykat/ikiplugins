#!/usr/bin/perl
# Javascript Search of Fields
# which applies search to records matching a SQL where clause
# in a SQLite database.
# Note that Javascript scrubbing MUST be turned off for the given page.
package IkiWiki::Plugin::jssearchreport;

use warnings;
use strict;
use IkiWiki 3.00;
use DBI;
use Data::Handle;
use Text::NeatTemplate;

sub import {
	hook(type => "getsetup", id => "jssearchreport", call => \&getsetup);
	hook(type => "preprocess", id => "jssearchreport", call => \&preprocess);
	hook(type => "pagetemplate", id => "jssearchreport", call => \&pagetemplate);
    IkiWiki::loadplugin("field");
    IkiWiki::loadplugin("sqlreport");
}

# ------------------------------------------------------------
# Global
# ----------------------------

my %ReportTables = ();

# ------------------------------------------------------------
# Hooks
# ----------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "search",
		},
}

sub preprocess (@) {
    my %params=@_;

    my $out = '';
    if ($params{page} eq $params{destpage}) {
	$out = set_up_search(%params);
    }
    else {
	# disable in inlined pages
    }
    return $out;
}

sub pagetemplate (@) {
    my %params=@_;

    my $template=$params{template};
    if ($ReportTables{$params{page}})
    {
        $template->param('datatablejq' => 1,
        'datatablejq_table' => $ReportTables{$params{page}}->{table},
        'datatablejq_options' => $ReportTables{$params{page}}->{options},
        'datatablejq_css' => $ReportTables{$params{page}}->{css},
        'datatablejq_yadcf' => $ReportTables{$params{page}}->{yadcf},
        );
    }
}
# ------------------------------------------------------------
# Private Functions
# ----------------------------
sub set_up_search {
    my %params=@_;
    my $master_page=$params{page};

    my %tvars = ();
    $tvars{formid} = ($params{formid} ? $params{formid} : 'jssearchreport');

    $ReportTables{$master_page}->{table} = "$tvars{formid}_table";
    $ReportTables{$master_page}->{options} =<<EOT;
"bProcessing": true,
"sPaginationType": "full_numbers",
EOT
    $ReportTables{$master_page}->{css} = '';
    $ReportTables{$master_page}->{yadcf} = '';

    my $fields=$params{fields};
    my @fields = split(' ', $fields);
    my @tagfields = ($params{tagfields}
	? split(' ', $params{tagfields})
	: ());
    my @sortfields = ($params{sortfields}
	? split(' ', $params{sortfields})
	: ());
    my %is_tagfield = ();
    foreach my $tag (@tagfields)
    {
	$is_tagfield{$tag} = 1;
    }

    $tvars{showfields} = '';
    if (@fields > 0)
    {
	$tvars{showfields} .=<<EOT;
showFields = new Array();
EOT
	my $ind = 0;
	foreach my $fn (@fields)
	{
	    $tvars{showfields} .=<<EOT;
showFields[$ind] = "$fn";
EOT
	    $ind++;
	}
    }
    $tvars{tagsets} = '';
    if (@tagfields > 0)
    {
	$tvars{tagsets} .=<<EOT;
tagFields = new Array();
EOT
	my $ind = 0;
	foreach my $fn (@tagfields)
	{
	    $tvars{tagsets} .=<<EOT;
tagFields[$ind] = "$fn";
EOT
	    $ind++;
	}
    }
    $tvars{sortfields} = '';
    if (@sortfields > 0)
    {
	$tvars{sortfields} .=<<EOT;
sortFields = new Array();
EOT
	my $ind = 0;
	foreach my $fn (@sortfields)
	{
	    $tvars{sortfields} .=<<EOT;
sortFields[$ind] = "$fn";
EOT
	    $ind++;
	}
    }
    $tvars{sort_fields} = '';
    foreach my $fn (@sortfields)
    {
        $tvars{sort_fields} .=<<EOT;
<input name="sort" type="radio" value="$fn"/><label for="sort">$fn</label>
EOT
    }

    my $report_start =<<EOT;
<table id="$tvars{formid}_table">
<thead><tr>
EOT
    my $row_template = '<tr>';
    my $i = 0;
    foreach my $fn (@fields)
    {
        $row_template .=<<EOT;
{?$fn <td class="$fn">[\$$fn]</td>!!<td class="empty"></td>}
EOT
        $report_start .=<<EOT;
<th>$fn</th>
EOT
        if ($is_tagfield{$fn})
        {
            $ReportTables{$master_page}->{yadcf} .=<<EOT;
{column_number : $i, text_data_delimiter: "|"},
EOT
        }
        else
        {
            $ReportTables{$master_page}->{yadcf} .=<<EOT;
{column_number : $i},
EOT
        }
        $i++;
    }
    $row_template .= "</tr>\n";
    $report_start .=<<EOT;
</tr></thead>
<tbody>
EOT
    my $report_end .=<<EOT;
</tbody>
</table>
EOT


    my $report = IkiWiki::Plugin::sqlreport::preprocess(%params,
        layout=>'bare',
        report_style=>'bare',
        row_template=>$row_template,
        report_class=>'',
        show=>$fields);

    $tvars{report} = $report_start . $report . $report_end;
##    my $handle = Data::Handle->new( __PACKAGE__ );
##    my $t = HTML::Template->new(filehandle => $handle);
##    $t->param(%tvars);
##
##    my $out = $t->output();
##    return $out;
    return $tvars{report};
} # set_up_search

1;

__DATA__
<script type='text/javascript'>
<!--
// Error strings
ERR_NoSearchTerms	= "You didn't enter any terms to search for, please enter some terms to search for and try again.";
ERR_NoResults		= "Your search found no results.";

<TMPL_IF SHOWFIELDS>
<TMPL_VAR SHOWFIELDS>
</TMPL_IF>
<TMPL_IF TAGSETS>
<TMPL_VAR TAGSETS>
</TMPL_IF>
<TMPL_IF SORTFIELDS>
<TMPL_VAR SORTFIELDS>
</TMPL_IF>

debug = function (log_txt) {
    if (window.console != undefined) {
        console.log(log_txt);
    }
}

// To sort an array in random order
Array.prototype.shuffle = function() {
var s = [];
while (this.length) s.push(this.splice(Math.random() * this.length, 1));
while (s.length) this.push(s.pop());
return this;
}

// Code from http://www.optimalworks.net/blog/2007/web-development/javascript/array-detection
function is_array(array) { return !( !array || (!array.length || array.length == 0) || typeof array !== 'object' || !array.constructor || array.nodeType || array.item ); }

function writeMessage(message) {
    var writeon = document.getElementById('message');
    writeon.innerHTML = message;
}

function initForm() {
    $(".<TMPL_VAR FORMID>_data ul").hide();
    $(".<TMPL_VAR FORMID>_data p").hide();
    writeMessage("Ready to search!")
}

//-->
</script>
<form id="<TMPL_VAR FORMID>" name="search" action="" method="get">
<table>
<TMPL_VAR SEARCH_FIELDS>
</table>
<span class="label">Sort:</span>
<input name="sort" type="radio" value="default" checked="yes"/><label for="sort">default</label>
<input name="sort" type="radio" value="random"/><label for="sort">random</label>
<TMPL_VAR SORT_FIELDS>
<input type="submit" value="Search!" name="search" />
<input type="reset" value="Reset" name="reset" />
</form>
<div id="message"></div>

<TMPL_VAR REPORT>

<script type='text/javascript'>
<!--
initForm();
//-->
</script>
