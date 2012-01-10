#!/usr/bin/perl
# Javascript Search of Fields
# which applies search to pages matching a PageSpec.
# Note that Javascript scrubbing MUST be turned off for the given page.
package IkiWiki::Plugin::jssearchfield;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "jssearchfield", call => \&getsetup);
	hook(type => "checkconfig", id => "jssearchfield", call => \&checkconfig);
	hook(type => "preprocess", id => "jssearchfield", call => \&preprocess);
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "search",
		},
		jssearchfield_css => {
			type => "string",
			example => "jssearchfield.css",
			description => "the location of the CSS file",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    if (!defined $config{jssearchfield_css})
    {
	$config{jssearchfield_css} = 'jssearchfield.css';
    }
    if ($config{jssearchfield_css} !~ /^(http|\/)/) # relative
    {
	$config{_jssearchfield_css_relative} = 1;
    }
}

sub preprocess (@) {
    my %params=@_;

    if ($params{page} eq $params{destpage}) {
	return set_up_search(%params);
    }
    else {
	# disable in inlined pages
	return "";
    }
}

# ------------------------------------------------------------
# Private Functions
# ----------------------------
sub set_up_search {
    my %params=@_;
    my $page=$params{page};

    my $pages=$params{pages};
    my $fields=$params{fields};

    my @matching_pages = pagespec_match_list($params{destpage},
	$pages,
	%params);

    if (@matching_pages == 0)
    {
	return '';
    }

    my @fields = split(' ', $fields);
    my @tagfields = ($params{tagfields}
	? split(' ', $params{tagfields})
	: ());
    my %is_tagfield = ();
    foreach my $tag (@tagfields)
    {
	$is_tagfield{$tag} = 1;
    }

    my $out = '';

    # The Javascript.
    # Note that we are creating all the Javascript inline,
    # because the code depends on which fields are being queried.
    # And also because it's simpler not to have to have an extra file.
    $out .=<<EOT;
<script type='text/javascript'>
<!--
// Error strings
ERR_NoSearchTerms	= "You didn't enter any terms to search for, please enter some terms to search for and try again.";
ERR_NoResults		= "Your search found no results.";

// Constructor for each search engine item.
// Used to create a record in the searchable "database"
function searchRec(ob) {
    for (x in ob)
    {
	this[x] = ob[x];
    }
    return this;
}

// See if the given value equals the value of the field
// If the field's value is an array, this will return true
// if ANY item of that array equals the given value
searchRec.prototype.field_equals = function(fn,val) {
    if (typeof val == 'undefined'
	|| val.length == 0)
    {
	return false;
    }
    else if (typeof this[fn] == 'undefined')
    {
	return false;
    }
    else if (typeof this[fn] == 'object')
    {
	for (var x = 0; x < this[fn].length; x++) {
	    if (this[fn][x] == val)
	    {
		return true;
	    }
	};
	return false;
    }
    else if (this[fn] == val)
    {
	return true;
    }
    return false;
}

// See if the given regex matches the value of the field
// If the field's value is an array, this will return true
// if ANY item of that array matches the given regex
searchRec.prototype.field_matches = function(fn,regex) {
    if (typeof regex == 'undefined'
	|| regex.length == 0)
    {
	return false;
    }
    else if (typeof this[fn] == 'undefined')
    {
	return false;
    }
    else if (typeof this[fn] == 'object')
    {
	for (var x = 0; x < this[fn].length; x++) {
	    if (this[fn][x].match(regex))
	    {
		return true;
	    }
	};
	return false;
    }
    else if (this[fn].match(regex))
    {
	return true;
    }
    return false;
}

// Check the value to see if it needs to be a regex
// and call equals or matches accordingly
searchRec.prototype.field_does_match = function(fn,qval) {
    if (typeof qval == 'undefined' || qval.length == 0)
    {
	return false;
    }
    var pos = qval.indexOf('='); 
    if (pos == 0) // starts with equals
    {
	var eqval = qval.substring(pos+1);
	return this.field_equals(fn,eqval);
    }
    else
    {
	var regex = new RegExp(qval,"i");
	return this.field_matches(fn,regex);
    }
    return false;
}

// Format the search rec as a HTML string
searchRec.prototype.as_html = function() {
	var out = "<li class=\\"result\\"><span class=\\"result-url\\">" + this.url + "</span>\\n";
EOT
    foreach my $fn (@fields)
    {
	if ($fn ne 'url' and $fn ne 'title')
	{
	    $out .=<<EOT;
	if (typeof this.$fn != 'undefined')
	{
	out = out + "<span class=\\"result-$fn\\">" + this.$fn + "</span>\\n";
	}
EOT
	}
    }
    $out .=<<EOT;
    out = out + "</li>\\n";

    return out;
}

// Grabs all the desired query values from a GET-style URL
// and constructs a query object
// Also updates the form
function queryRec() {

	// get the string following the question mark
	var queryString = location.href.substring(location.href.indexOf("?")+1);

	// split parameters into pairs, assuming pairs are separated by ampersands
	var pairs = queryString.split("&");

	var myform = document.getElementById("jssearchfield");

	// for each pair, we get the name and the value
	var found = false;
	for (var i = 0; i < pairs.length; i++) { 
		var pos = pairs[i].indexOf('='); 
		if (pos == -1) {
			continue; 
		}
		var argname = pairs[i].substring(0,pos);
		var argvalue = pairs[i].substring(pos+1); 

		// Replaces "Google-style" + signs with the spaces
		// they represent
		argvalue = unescape(argvalue.replace(/\\+/g, " "));
		if (argvalue.length > 0)
		{
		    if (myform[argname].type == 'text')
		    {
			myform[argname].value = argvalue;
			this[argname] = argvalue.split(" ");
		    }
		    else if (myform[argname].length > 0)
		    {
			for (j=0; j < myform[argname].length;j++)
			{
			    if (myform[argname][j].value == argvalue)
			    {
				myform[argname][j].checked = true;
			    }
			}
			if (typeof this[argname] == 'undefined')
			{
			    this[argname] = [argvalue];
			}
			else
			{
			    this[argname][this[argname].length] = argvalue;
			}
		    }
		    else
		    {
			this[argname] = [argvalue];
		    }
		    if (argname != "search")
		    {
			found = true;
		    }
		}
	}
	this["_terms"] = found;
	return this;
}

queryRec.prototype.as_html = function() {
	var out = "";
	for (x in this)
	{
	    if (x != "search"
		&& x != "_terms"
		&& typeof this[x] != "function"
		&& typeof this[x] != "undefined")
	    {
		var qv = "";
		for (var i = 0; i < this[x].length; i++)
		{
		    if (this[x][i].length > 0)
		    {
			qv = qv + this[x][i] + " ";
		    }
		}
		if (qv.length > 0)
		{
		    out = out + x + "=<b>" + qv + "</b> ";
		}
	    }
	}
    return out;
}

// Code from http://www.optimalworks.net/blog/2007/web-development/javascript/array-detection
function is_array(array) { return !( !array || (!array.length || array.length == 0) || typeof array !== 'object' || !array.constructor || array.nodeType || array.item ); }

function doSearch (query) {

    if (!query["_terms"]) {
	return ERR_NoSearchTerms;
    }

    // This is where we will be putting the results.
    results = new Array();

    // Loop through the db for potential results
    // For every entry in the "database"
    for (sDB = 0; sDB < searchDB.length; sDB++) {
	    matches_all_terms = true; //matches until it does not
EOT
    foreach my $fn (@fields)
    {
	$out .=<<EOT;
	if (typeof query["$fn"] != 'undefined')
	{
		// For every search term we are working with
		for (var t = 0; t < query["$fn"].length; t++) {
		    matches_this_term = false;
		    var q = query["$fn"][t];
		    if (searchDB[sDB].field_does_match("$fn",q)) {
			matches_this_term = true;
		    }
		    if (!matches_this_term)
		    {
			matches_all_terms = false;
		    }
		}
	}
EOT
    }
    $out .=<<EOT;
	    if (matches_all_terms)
	    {
		results[results.length] = String(sDB);
	    }
    }
	if (results.length > 0) {
		return results;
	}
	else {
		return ERR_NoResults;
	}
}

function initForm() {
    var search_form = document.getElementById('jssearchfield');
    search_form.setAttribute("action", document.location.pathname);

    document.writeln("<p>Ready to search!</p>");
}

function formatResults(query,results) {
	// Loop through them and make it pretty! :)
	if (is_array(results)) {
		document.writeln("<p>Searched for " + query.as_html() + " Found " + results.length + " results.</p>");
	
		document.writeln("<ol>");
		for (r = 0; r < results.length; r++) {
			result = searchDB[results[r]];
			
			document.writeln(result.as_html());
		}
		document.writeln("</ol>");
	}
	// If it is not an array, then we got an error message, so display that
	// rather than results
	else {
		document.writeln("<i>" + results + "</i>");
		document.writeln("<br />");
	}
	document.writeln("<br/>\\n<a href=\\"#jssearchfield\\">&raquo; Back to search form</a>\\n");
}
EOT

    # the array of records
    $out .=<<EOT;
searchDB = new Array();
EOT

    my %tagsets = ();
    for (my $i = 0; $i < @matching_pages; $i++)
    {
	my $pn = $matching_pages[$i];
	$out .=<<EOT;
searchDB[$i] = new searchRec({
EOT
	my $title = IkiWiki::Plugin::field::field_get_value('title', $pn);
	my $url = htmllink($params{page}, $params{destpage}, $pn, linktext=>$title);
	$url =~ s/"/'/g; # use single quotes so as not to mess up the double quotes
	$out .= 'url:"'.$url.'",';
	foreach my $fn (@fields)
	{
	    $tagsets{$fn} = {} if ($is_tagfield{$fn} and !exists $tagsets{$fn});
	    my $val = IkiWiki::Plugin::field::field_get_value($fn, $pn);
	    if (ref $val eq 'ARRAY')
	    {
		my @vals = ();
		foreach my $v (@{$val})
		{
		    $v =~ s/"/'/g;
		    push @vals, '"'.$v.'"';
		    if ($is_tagfield{$fn})
		    {
			$tagsets{$fn}{$v} = 0 if !exists $tagsets{$fn}{$v};
			$tagsets{$fn}{$v}++;
		    }
		}
		$out .= $fn.':['.join(',', @vals).'],';
	    }
	    elsif ($val)
	    {
		$val =~ s/"/'/g;
		$out .= $fn.':"'.$val.'",';
		if ($is_tagfield{$fn})
		{
		    $tagsets{$fn}{$val} = 0 if !exists $tagsets{$fn}{$val};
		    $tagsets{$fn}{$val}++;
		}
	    }
	}
	$out .= "});\n";
    }

    # and the tagsets
    if (@tagfields > 0)
    {
	$out .=<<EOT;
tagSets = new Object();
EOT
	foreach my $fn (@tagfields)
	{
	    $out .=<<EOT;
	tagSets["$fn"] = [
EOT
	    foreach my $tag (sort keys %{$tagsets{$fn}})
	    {
		$out .=<<EOT;
	    {tag:"$tag",freq:$tagsets{$fn}{$tag}},
EOT
	    }
	    $out .=<<EOT;
	];
EOT
	}
    }
    $out .=<<EOT;
//-->
</script>
EOT
    # The search form
    $out .=<<EOT;
<form id="jssearchfield" name="search" action="" method="get">
<table>
EOT
    foreach my $fn (@fields)
    {
	$out .= "<tr><td class='label'>$fn:</td><td>";
	if ($is_tagfield{$fn})
	{
	    $out .= "<ul class='taglist'>\n";
	    my $count = 0;
	    foreach my $tag (sort keys %{$tagsets{$fn}})
	    {
		$out .=<<EOT;
<li><input name="$fn" type="checkbox" value="$tag" />
<label for="$fn">$tag ($tagsets{$fn}{$tag})</label></li>
EOT
		$count++;
		if ($count %10 == 0)
		{
		    $out .= "</ul>\n<ul class='taglist'>\n";
		}
	    }
	    $out .= "</ul>\n";
	}
	else
	{
	    $out .=<<EOT
<input type="text" name="$fn" size="60"/>
EOT
	}
	$out .= "</td></tr>\n";
    }
    $out .=<<EOT;
</table>
<input type="submit" value="Search!" name="search" />
</form>

<script type='text/javascript'>
<!--
initForm();

var query = new queryRec();
if (query["search"]) {
    var results = doSearch(query);
    if (results) {
        formatResults(query,results);
    }
}
//-->
</script>
EOT

} # set_up_search

1
