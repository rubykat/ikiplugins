#!/usr/bin/perl
# Convert pages to PDF (from HTML) using wkhtmltopdf
package IkiWiki::Plugin::html2pdf;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Spec;
use File::Path;
use File::Temp ();

sub import {
	hook(type => "getsetup", id => "html2pdf", call => \&getsetup);
	hook(type => "checkconfig", id => "field", call => \&checkconfig);
	hook(type => "sanitize", id => "html2pdf", call => \&sanitize);
	hook(type => "change", id => "html2pdf", call => \&change);
}

# --------------------------------------------------------------
# Hooks
# --------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 1,
		},
		html2pdf_pages => {
			type => "string",
			example => "docs/*",
			description => "pages to render into PDF",
			safe => 0,
			rebuild => undef,
		},
		html2pdf_prog => {
			type => "string",
			example => "/usr/local/bin/wkhtmltopdf",
			description => "the location of the wkhtmltopdf program",
			safe => 0,
			rebuild => undef,
		},
		html2pdf_args => {
			type => "string",
			example => "-p None",
			description => "arguments for the wkhtmltopdf program",
			safe => 0,
			rebuild => undef,
		},
		html2pdf_css => {
			type => "string",
			example => "http://www.example.com/styles/print.css",
			description => "the location a user style sheet",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    if (!defined $config{html2pdf_prog})
    {
	$config{html2pdf_prog} = 'wkhtmltopdf';
    }
    if (!defined $config{html2pdf_pages})
    {
	error("Must define html2pdf_pages");
    }
} # checkconfig

# Make all the IMG links relative for pages
# which we are converting to PDF
# (converts /foo into ../../../foo or similar)
# We need to do this because we are reading the HTML from a file,
# not from a web-server.
#
# Taken from http://ikiwiki.info/plugins/contrib/siterel2pagerel/
sub sanitize (@) {
    my %params = @_;
    my $page = $params{page};

    if (pagespec_match($page, $config{html2pdf_pages}))
    {
	# note whether we are rendering PDF version of file
	my $basename = IkiWiki::basename($page);
	my $pdf_dest=targetpage($page, 'pdf', $basename);
	will_render($page, $pdf_dest);

	my $baseurl=IkiWiki::baseurl($page);
	my $content=$params{content};
	$content=~s/(<img(?:\s+(?:class|id|width|height|alt|title)\s*="[^"]+")*)\s+src=\s*"\/([^"]*)"/$1 src="$baseurl$2"/mig;
	return $content;
    }
    return $params{content};
} # sanitize

# create the PDF version of the file
sub change (@) {
    my @files=@_;
    foreach my $file (@files)
    {
	my $page=pagename($file);
	if (pagespec_match($page, $config{html2pdf_pages}))
	{
	    create_pdf_file(page=>$page);
	}
    }
} # change

# --------------------------------------------------------------
# Private Functions
# --------------------------------
sub create_pdf_file (@) {
    my %params = @_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return 0;
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return 0;
    }
    debug("html2pdf PDF file for $page");

    # find the HTML file which was rendered
    my $html_page = htmlpage($page);

    # This uses the HTML file that has been written;
    # since this is called in "change", the file ought to exist
    my $in_file = File::Spec->catfile($config{destdir}, $html_page);
    if (!-e $in_file)
    {
	debug("$in_file not found");
	return 0;
    }

    my $basename = IkiWiki::basename($page);
    my $pdf_dest=targetpage($page, 'pdf', $basename);
    my $out_dest = File::Spec->catfile($config{destdir}, $pdf_dest);

    my $cmd = "$config{html2pdf_prog} $config{html2pdf_args}";
    if ($config{html2pdf_css})
    {
	$cmd .= "  --user-style-sheet $config{html2pdf_css}";
    }
    my $fh;
    if ($config{html2pdf_cover})
    {
	$fh = File::Temp->new(TMPDIR=>1,
			      TEMPLATE=>'htpXXXXXX',
			      SUFFIX=>'.html');
	create_cover_file(%params,
			  tmp_file=>$fh,
			  template=>$config{html2pdf_cover});
	my $fname = $fh->filename;
	$cmd .= " cover $fname";
    }
    $cmd .= " page $in_file";
    $cmd .= " $out_dest";
    system($cmd) == 0 or die "FAILED: $cmd";

    return 1;
} # create_pdf_file

sub create_cover_file (@) {
    my %params = @_;
    my $page = $params{page};

    my $title = (
	exists $pagestate{$page}{meta}{title}
	? $pagestate{$page}{meta}{title}
	: pagetitle(IkiWiki::basename($page))
    );
    # capitalize the title
    $title =~ s/ (
                 (^\w)    #at the beginning of the line
                   |      # or
                 (\s\w)   #preceded by whitespace
                   )
                /\U$1/xg;


    my $template;
    eval {
	# Do this in an eval because it might fail
	# if the template isn't a page in the wiki
	$template=template_depends($params{template}, $params{page},
				   blind_cache => 1);
    };
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$params{template}.tmpl",
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $params{template}.tmpl:")." $@";
	}
	if (! $template) {

	    error sprintf(gettext("%s not found"),
			  htmllink($params{page}, $params{destpage},
				   "/templates/$params{template}"))
	}
    }
    $template->param('title' => $title);

    my $content = $template->output;
    my $fh = $params{tmp_file};
    print $fh $content;
} # create_cover_file

1;
