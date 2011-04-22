#!/usr/bin/perl
# Ikiwiki thumblist plugin. Replace "thumblist" with the name of your plugin
# in the lines below, remove hooks you don't use, and flesh out the code to
# make it do something.
package IkiWiki::Plugin::thumblist;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Basename;

sub import {
	hook(type => "getsetup", id => "thumblist",  call => \&getsetup);
	hook(type => "preprocess", id => "thumblist", call => \&preprocess, scan=>1);
}

#------------------------------------------------------------------
# Hooks
#------------------------------------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};
    my $pages = (defined $params{pages} ? $params{pages} : "${page}/*.jpg or ${page}/*.gif or ${page}/*.png");
    my $size = (defined $params{size} ? $params{size} : "100x100");

    # find the images related to this page
    my $deptype=deptype("presence");
    my @images;
    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do
    if ($params{trail})
    {
	my @trailpages = split(/,/, $params{trail});
	foreach my $tp (@trailpages)
	{
	    push @images, @{$links{$tp}};
	}
	if ($params{pages})
	{
	    @images = pagespec_match_list($params{destpage}, $pages,
						  %params,
						  deptype => $deptype,
						  list=>\@images);
	}
    }
    else
    {
	@images = pagespec_match_list($params{destpage}, $pages,
				      %params,
				      deptype => $deptype);
    }

    my $start = ($params{start} ? $params{start} : 0);
    my $end = ($params{end} ? $params{end} : @images);

    my @list = ();
    for (my $i=$start; $i < @images and $i < $end; $i++)
    {
	my $img_loc = $images[$i];
	$img_loc =~ m{(.*)/([-\w]+\.\w+)};
	my $img_dir = $1;
	my $img = $2;
	my $imgtag = process_image($img => 1,
				   %params,
				   img_dir=>$img_dir,
				   size=>$size,
				   first=>($i == 0),
				   last=>($i == $#images));
	push @list, $imgtag;
    }

    return join('', @list);
} # preprocess

#------------------------------------------------------------------
# Private Functions
#------------------------------------------------------------------

sub process_image (@) {
	my ($image) = $_[0] =~ /$config{wiki_file_regexp}/; # untaint
	my %params=@_;

	if (! exists $params{size}) {
		$params{size}='full';
	}

	add_link($params{page}, $image);
	add_depends($params{page}, $image);

	# optimisation: detect scan mode, and avoid generating the image
	if (! defined wantarray) {
		return '';
	}

	my $file = bestlink($params{img_dir}, $image);
	my $srcfile = srcfile($file, 1);
	if (! $file || ! defined $srcfile) {
		return htmllink($params{img_dir}, $params{destpage}, $image);
	}

	my $dir = $params{img_dir};
	my $base = IkiWiki::basename($file);

	eval q{use Image::Magick};
	error gettext("Image::Magick is not installed") if $@;
	my $im = Image::Magick->new;
	my $imglink;
	my $r = $im->Read($srcfile);
	error sprintf(gettext("failed to read %s: %s"), $file, $r) if $r;

	my ($dwidth, $dheight);

	if ($params{size} ne 'full') {
	    my ($in_w, $in_h) = ($params{size} =~ /^(\d+)x(\d+)$/);
	    error sprintf(gettext('wrong size format "%s" (should be WxH)'),
			  $params{size})
		unless (defined $in_w && defined $in_h && $in_w && $in_h);

	    # calculate the thumbnail width and height
	    my $src_w = $im->Get("width");
	    my $src_h = $im->Get("height");
	    my $src_pixels = $src_w * $src_h;
	    my $thumb_pixels = $in_w * $in_h;
	    my $new_w = int($src_w / (sqrt($src_w * $src_h) / sqrt($thumb_pixels)));
	    my $new_h = int($src_h / (sqrt($src_w * $src_h) / sqrt($thumb_pixels)));
	    if (($new_w > $src_w) || ($new_h > $src_w))
	    {
		# resizing larger
		$imglink = $file;

		# don't generate larger image, just set display size
		if ($new_w && $new_h) {
		    ($dwidth, $dheight)=($new_w, $new_h);
		}
		# avoid division by zero on 0x0 image
		elsif ($src_w == 0 || $src_h == 0) {
		    ($dwidth, $dheight)=(0, 0);
		}
	    }
	    else {
		# resizing smaller
		my $outfile = "$config{destdir}/$dir/${in_w}x${in_h}-$base";
		$imglink = "$dir/${in_w}x${in_h}-$base";

		will_render($params{page}, $imglink);

		if (-e $outfile && (-M $srcfile >= -M $outfile)) {
		    $im = Image::Magick->new;
		    $r = $im->Read($outfile);
		    error sprintf(gettext("failed to read %s: %s"), $outfile, $r) if $r;

		    $dwidth = $im->Get("width");
		    $dheight = $im->Get("height");
		}
		else {

		    ($dwidth, $dheight)=($new_w, $new_h);
		    $r = $im->Resize(geometry => "${new_w}x${new_h}");
		    error sprintf(gettext("failed to resize: %s"), $r) if $r;

		    # don't actually write file in preview mode
		    if (! $params{preview}) {
			my @blob = $im->ImageToBlob();
			writefile($imglink, $config{destdir}, $blob[0], 1);
		    }
		    else {
			$imglink = $file;
		    }
		}
	    }
	}
	else {
		$imglink = $file;
		$dwidth = $im->Get("width");
		$dheight = $im->Get("height");
	}
	
	if (! defined($dwidth) || ! defined($dheight)) {
		error sprintf(gettext("failed to determine size of image %s"), $file)
	}

	my ($fileurl, $imgurl);
	if (! $params{preview}) {
		$fileurl=urlto($file, $params{destpage});
		$imgurl=urlto($imglink, $params{destpage});
	}
	else {
		$fileurl="$config{url}/$file";
		$imgurl="$config{url}/$imglink";
	}

	my $alt=($params{alt} ? $params{alt} : $base);
	my @exif_fields = ($params{exif} ? split(/,/, $params{exif}) : ());

	# use a template to generate the display code
	my $template_id = ($params{template} ? $params{template} : 'thumblist.tmpl');
	my $template=IkiWiki::template($template_id);
	$template->param(
	    width=>$dwidth,
	    height=>$dheight,
	    url=>$fileurl,
	    thumb_url=>$imgurl,
	    class=>$params{class},
	    caption=>get_caption(%params,
				 exif_fields=>\@exif_fields,
				 srcfile=>$srcfile),
	    alt=>$alt,
	    first=>$params{first},
	    last=>$params{last},
	);
	my $imgtag = $template->output;
	return $imgtag;
}

sub get_caption {
    my %params=@_;

    my $srcfile = $params{srcfile};
    
    eval q{use Image::ExifTool};
    error gettext("Image::ExifTool is not installed") if $@;
    my @out = ();
    if ($params{caption})
    {
	push @out, $params{caption};
    }
    if (-e $srcfile and $params{exif_fields})
    {
	my $info = Image::ExifTool::ImageInfo($srcfile);
	# add the basename
	my ($basename, $path, $suffix) = fileparse($srcfile, qr/\.[^.]*/);
	$basename =~ s/_/ /g;
	$info->{FileBase} = $basename;

	# only add the meta data if it's there
	foreach my $fieldspec (@{$params{exif_fields}})
	{
	    $fieldspec =~ /%([\w\s]+)%/;
	    my $field = $1;
	    if (exists $info->{$field}
		and defined $info->{$field}
		and $info->{$field})
	    {
		my $val = $fieldspec;
		my $fieldval = $info->{$field};
		# make the fieldval HTML-safe
		$fieldval =~ s/&/&amp;/g;
		$fieldval =~ s/</&lt;/g;
		$fieldval =~ s/>/&gt;/g;
		$val =~ s/%${field}%/$fieldval/g;
		push @out, $val;
	    }
	}
    }
    return join("\n", @out);
} # get_caption

1
