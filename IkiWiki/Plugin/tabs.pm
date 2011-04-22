#!/usr/bin/perl
package IkiWiki::Plugin::tabs;

use warnings;
use strict;
use IkiWiki 3.00;

our %TabIDs = ();
sub import {
	hook(type => "getsetup", id => "tabs", call => \&getsetup);
	hook(type => "preprocess", id => "tabs",
		call => \&preprocess_tabs);
	hook(type => "format", id => "tabs", call => \&format);
}

# ---------------------------------------------------------
# Hooks
# --------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub preprocess_tabs (@) {
    my %params= (
		 id => 'tabs',
		 @_
		);

    my $page_type = pagetype($pagesources{$params{page}});
    # perform htmlizing on content on HTML pages
    $page_type = $config{default_pageext} if $page_type eq 'html';

    # make the list of tabs by looking at the *_label params
    # and their content by looking at the *_content params;
    my %labels = ();
    my %texts = ();
    foreach my $key (keys %params)
    {
	if ($key =~ /(\w+)_label/)
	{
	    $labels{$1} = $params{$key};
	}
	elsif ($key =~ /(\w+)_content/)
	{
	    $texts{$1} = $params{$key};
	}
    }

    # Build the list of links, and the content divs
    # Note that this assumes that every label has associated content
    my @divs = ();
    my @links = ();
    push @links, '<ul>';
    foreach my $key (sort keys %labels)
    {
	my $id=genid($params{page}, $key);
	push @links, "<li><a href=\"#$id\"><span>$labels{$key}</span></a></li>";

	my $text = $texts{$key};
	# HTMLize the text
	$text = IkiWiki::htmlize($params{page},
				 $params{destpage},
				 $page_type,
				 $text) unless (!$page_type);
	# Preprocess the text to expand any preprocessor directives
	# embedded inside it.
	$text= IkiWiki::preprocess
	    ($params{page},
	     $params{destpage}, 
	     IkiWiki::filter($params{page},
			     $params{destpage},
			     $text)
	    );
	push @divs, sprintf("<div id=\"%s\">\n%s\n</div>\n",
	    $id, $text);
    }
    push @links, '</ul>';

    my $tab_id=genid($params{page}, $params{id});
    # remember the tab ID
    if (!exists $TabIDs{$params{page}})
    {
	$TabIDs{$params{page}} = {};
    }
    $TabIDs{$params{page}}->{$tab_id} = 1;

    return sprintf('<div class="tabs" id="%s">', $tab_id)
    . join("\n", @links)
    . "\n"
    . join("\n", @divs)
    . "\n</div>\n";

}

sub format (@) {
    my %params=@_;

    if ($params{content}=~/<div class="tabs"/)
    {
	# if jquery is already in the header, remove it
	$params{content}=~s!<script [^>]*?src="[^"]*/jquery[-.\w]*\.js"[^>]*?>\s*</script>!!s;
	if (! ($params{content}=~s!(\s*</head>)!include_javascript($params{page}).$1!em))
	{
	    # no <head> tag, probably in preview mode
	    $params{content}=include_javascript($params{page}, 1).$params{content};
	}
    }
    return $params{content};
}

# ---------------------------------------------------------
# Private Functions
# --------------------

sub genid ($$) {
	my $page=shift;
	my $id=shift;

	$id="$page.$id";

	# make it a legal html id attribute
	$id=~s/[^-a-zA-Z0-9]/-/g;
	if ($id !~ /^[a-zA-Z]/) {
		$id="id$id";
	}
	return $id;
}

sub include_javascript ($;$) {
    my $page=shift;
    my $absolute=shift;
	
    my $jqu_css = $config{tabs_jquery_ui_css};
    my $jq_js = $config{tabs_jquery_js};
    my $jqu_js = $config{tabs_jquery_ui_js};
    my $out = '';

    $out =<<EOT;
<link href="${jqu_css}" rel="stylesheet" type="text/css"/>
<script src="${jq_js}" type="text/javascript"></script>
<script src="${jqu_js}" type="text/javascript"></script>
<script>
<!--
\$(document).ready(function() {
EOT
    foreach my $id (sort keys %{$TabIDs{$page}})
    {
	$out .=<<EOT;
    \$("#$id").tabs();
EOT
    }
    $out .=<<EOT;
  });
//-->
</script>
EOT
    return $out;
}

1
