package CONSITE::Alignment;


use vars qw(@ISA $AUTOLOAD);
use CGI qw(:standard);
use TFBS::Matrix::PWM;
use TFBS::Matrix::PFM;
use TFBS::Matrix;
use Bio::Seq;
use Bio::SimpleAlign;
use DBI;
use GD;
use PDL;
use IO::String;
use CONSITE::Analysis;
use Class::MethodMaker
    get_set => [qw(cutoff window
		   alignseq1 alignseq2
		   fsiteset1 fsiteset2
		   seq1name seq2name
		   seq1length seq2length
		   conservation1 conservation2
		   REL_CGI_BIN_DIR
		   ABS_TMP_DIR
		   REL_TMP_DIR
		   start_at end_at)],
    list    => [qw(alignseq1array alignseq2array)],
    hash    => [qw(seq1siteset seq2siteset)],      # unused?
    new_with_init => ['new'];


use strict;

use constant IMAGE_WIDTH =>600;
use constant IMAGE_MARGIN =>50;

my @seq1RGB   = (48, 176, 200);
my @seq2RGB   = (31, 225,   0);
my $seq1hex   = "#30B0C8";
my $seq2hex   = "#1FD100";
my $seq1bghex = "#CCFFFF";
my $seq2bghex = "#CCFFCC";

@ISA =('CONSITE::Analysis');


sub init  {

    # this is ugly; it simply cries for refactoring

    my ($self, %args) = @_;
    $self->{job} = $args{-job};
    $self->{seqobj1} = $args{-seqobj1};
    $self->window($args{-window} or 50);
    $self->REL_TMP_DIR($args{-rel_tmp_dir});
    $self->ABS_TMP_DIR($args{-abs_tmp_dir});
    $self->REL_CGI_BIN_DIR($args{-rel_cgi_bin_dir});

    $self->_parse_alignment($args{-alignstring} );
    $self->seq1length(length(_strip_gaps($self->alignseq1())));
    $self->seq2length(length(_strip_gaps($self->alignseq2())));
    #$self->seq3length($self->job
    $self->conservation1($self->_calculate_conservation($self->window(),1));
    $self->conservation2($self->_calculate_conservation($self->window(),2));
    $self->_do_sitesearch(($args{-MatrixSet}), $self->{job}->threshold(),
			  $self->cutoff($args{-cutoff}
					or $self->{job}->cutoff()
					or $self->{job}->cutoff($self->_calculate_cutoff())));

    $self->_set_start_end(%args);
    return $self;

}


sub _set_start_end  {

    # start and end are set relative to the alignment !!!
    my ($self, %args) = @_;

    # calculate overlap - temporary
    if (defined($args{-start}) and defined($args{-end}))  {
	no strict 'refs';
	my $rangeref = ($self->{job}->rangeref() or 1);
	my $seqstrlen ="seq".$rangeref."length";
	my $reflength = $self->$seqstrlen;
	use strict 'refs';

	# flip start, end if reversed

	if ($args{-start} > $args{-end})  {
	    ($args{-start}, $args{-end}) = ($args{-end}, $args{-start});
	}

	# try to set start_at

	my $start_at =
	   ( # if legal
	    $self->pdlindex($args{-start}, $rangeref=>0)
	    # else if negative, try to slide upstream
	    or ($args{-start}<1 ?
		($self->pdlindex(1,$rangeref=>0) + $args{-start}):0)
	    #else if bigger than length, try to slide downstream
		or ($args{-start}>$reflength
		    ?
		    $self->pdlindex($reflength,$rangeref=>0)
		     +$args{-start} - $reflength
		    : 1));

	# still overflows?
	if ($args{-start} > $reflength)  {
	    $start_at = $self->pdlindex()->getdim(0)
		- IMAGE_WIDTH
		    + 2*IMAGE_MARGIN;
	}
	$start_at = 1 if $start_at < 1;

	# try to set end_at

	my $end_at =
	   ( # if legal
	    $self->pdlindex($args{-end}, $rangeref=>0)
	    # else if negative, try to slide upstream
	    or ($args{-end}<1 ?
		($self->pdlindex(1,$rangeref=>0) - $args{-end}):0)
	    #else if bigger than length, try to slide downstream
		or ($args{-end}>$reflength
		    ?
		    $self->pdlindex($reflength,$rangeref=>0)
		     +$args{-end} - $reflength
		    :
		    $self->pdlindex()->getdim(0)));
	$end_at = IMAGE_WIDTH - 2*IMAGE_MARGIN  if $end_at < $start_at;
	$end_at =  $self->pdlindex->getdim(0)
	    if $end_at >$self->pdlindex()->getdim(0);

	$self->start_at($start_at); $self->{job}->start_at($start_at);
	$self->end_at($end_at);     $self->{job}->end_at($end_at);
    }
    else {
	my $overlap_slice1 =
	    $self->pdlindex->slice(':,1')->where(($self->pdlindex->slice(':,2')>0));
	$overlap_slice1 = $overlap_slice1->where($overlap_slice1>0);
	my ($overlap_start, $overlap_end);
	eval { ($overlap_start, $overlap_end) =
	    ($self->pdlindex(list ($overlap_slice1->slice(0)),  1=>0),
	     $self->pdlindex(list ($overlap_slice1->slice(-1)), 1=>0)); };
	if ($@) { # gee, no overlap
	    $self->start_at(1);$self->end_at($self->pdlindex->getdim(0));
	    return;
	};

	if ($overlap_end -  $overlap_start < (IMAGE_WIDTH-2*IMAGE_MARGIN)) {
	    $overlap_start =
		int ($overlap_start + ($overlap_end - $overlap_start)/2
		     -(IMAGE_WIDTH-2*IMAGE_MARGIN)/2);
	    $overlap_end =
		int ($overlap_start + ($overlap_end-$overlap_start)/2
		     +(IMAGE_WIDTH-2*IMAGE_MARGIN)/2);
	    $overlap_start=1 if $overlap_start<1;
	    $overlap_end = $self->pdlindex->getdim(0)
		if $overlap_end > $self->pdlindex->getdim(0);

	}
	$self->start_at($overlap_start);
	$self->end_at($overlap_end);
    }

}



sub DESTROY {
    my $self = shift;
    delete $self->{job};
}

sub HTML_table {
    my ($self) = @_;
    my $table = Tr (th({-rowspan=>2},"Transcription factor").
		    th({-colspan=>6, -bgcolor=>$seq1bghex}, $self->seq1name),
		    th({-colspan=>6, -bgcolor=>$seq2bghex}, $self->seq2name));
    $table .= Tr(td({-colspan=>2,-bgcolor=>$seq1bghex}, "Sequence").
		 td({-bgcolor=>$seq1bghex},[qw(From To Score Strand)]).
		 td({-colspan=>2,-bgcolor=>$seq2bghex}, "Sequence").
		 td({-bgcolor=>$seq2bghex},[qw(From To Score Strand)]))."\n";

    my $iterator1 = $self->fsiteset1->Iterator(-sort_by=>'start');
    my $iterator2 = $self->fsiteset2->Iterator(-sort_by=>'start');

    my ($s, $e) = ($self->start_at(),$self->end_at());

    my ($site1, $site2);
    if ($self->fsiteset1->size > 0) {
		do {$site1 = $iterator1->next()} until $site1->start >=$s;
		do {$site2 = $iterator2->next()} until $site2->start >=$self->pdlindex($s, 1=>2);
    }
    else {
		$table = Tr(td(p({-style=>"font-size:16px", -align=>"center"}, "No binding sites detected.")));
    }

    while (defined $site1 and defined $site2 and $site1->start < $e)  {
		my $color = "white";

		if ($self->pdlindex($site1->start(), 1=>3) == 1) { #exon
			$color = "#ffff7f";
		}
		elsif ($self->pdlindex($site1->start(), 1=>3) == 2) { #orf
			$color = "#ff7f7f";
		}

		my $Name = $site1->Matrix->{name};
		my $Url = $self->REL_CGI_BIN_DIR."/jaspartf?ID=".$site1->Matrix->{ID}.
			"&score1=".$site1->score().
			"&score2=".$site2->score().
				"&pos1=".$self->_abs_pos($site1->start(),1).
				"&pos2=".$self->_abs_pos($site2->start(),2).
					"&seq1=".$self->seq1name().
					"&seq2=".$self->seq2name().
						"&name=".$site1->Matrix->{name}.
						"&jobID=".$self->{job}->jobID()."";
		$table .= Tr(td({-bgcolor=>$color},
				a({ -onClick=>
					"window.open('$Url', 'TFprofile', ".
					"'height=400,width=500,toolbar=no,menubar=no,".
					"scrollbars=yes,resizable=yes'); return false;",
					 -href=>$Url, -target=>'_blank'
					 },$site1->Matrix->{name})).
				 td({-bgcolor=>$seq1bghex}, "&nbsp;").
				 td({-bgcolor=>$color},
				[
				 _plussiteseq($site1), #$site1->siteseq(),
				 $self->_abs_pos($site1->start(),1),
				 $self->_abs_pos($site1->end(),1),
				 $site1->score(),
				 ($site1->strand()=="-1"?"-":"+") # $site1->strand()
				]).
				 td({-bgcolor=>$seq2bghex}, "&nbsp;").
				 td({-bgcolor=>$color},
				[
				 _plussiteseq($site2), #$site2->siteseq(),
				 $self->_abs_pos($site2->start(),2),
				 $self->_abs_pos($site2->end(),2),
				 $site2->score(),
				 ($site2->strand()=="-1"?"-":"+") #$site2->strand()
				]
				))
			."\n";
		$site1 = $iterator1->next();
		$site2 = $iterator2->next();
    }

	my $page_id = sprintf("%04d", int rand(10000));
    my $image = $self->_drawaln_png();
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".ALN.png");
    print OUT $image->png();
    close OUT;
	my $graphtable = table(Tr(td(img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".ALN.png"}))));

    return (table({-border=>1, -valign=>"top", -style=>"font-size:12px"}, $table), $graphtable);

}


sub HTML_alignment {
    my ($self) = @_;

    my $TITLE_AREA  = (length($self->seq1name) >length($self->seq2name)) ?
	length($self->seq1name) : length($self->seq2name);
    my $TICKS_EVERY = 10;
    my $BLOCK_WIDTH = 60;
    my $SITE_SHIFT  = 3;
    my ($lastindex1, $lastindex2, );
    my $outstring ="";
    my $iterator1 = $self->fsiteset1->Iterator(-sort_by=>'start');
    my $iterator2 = $self->fsiteset2->Iterator(-sort_by=>'start');

	my $START_TIME=time;
    my ($s, $e) = ($self->start_at(),$self->end_at());

    my $blockstart= ($s or 1);
    my ($site1, $site2);
	if ($self->fsiteset1->size > 0) {
		do {$site1 = $iterator1->next()} until $site1->start >=$s;
		do {$site2 = $iterator2->next()} until $site2->start >=$self->pdlindex($s, 1=>2);
    }
    else {
	#	$table = Oup({-style=>"font-size:16px", -align=>"center"}, "No binding sites detected.")));
    }
    my @alnarray1 = ($self->alignseq1array)[0..$e];
	my @alnarray2 = ($self->alignseq2array);#[0..$self->pdlindex($e, 1=>2)];

    do {
		my ($seq1slice, $seq2slice, $identity_bars, $ruler_bars, $ruler);
		my $seq1_ruler = " "x($TITLE_AREA +4);
		my $seq2_ruler = " "x($TITLE_AREA +4);
		my $seq1_ruler_bars;
		my $seq2_ruler_bars;
		my $span_open=0;

		for my $i ($blockstart..($blockstart+$BLOCK_WIDTH-1)) {
			last unless defined ($alnarray1[$i]);

			# record the actual sequences and conservation bar

			$seq1slice .= $alnarray1[$i];
			$seq2slice .= $alnarray2[$i];

			# ruler and ticks

			# alignment ruler - currently not used
			#if (($i % $TICKS_EVERY) == 0)  {
			#	$ruler_bars .= sprintf("%".$TICKS_EVERY."s", '|');
			#	$ruler      .= sprintf("%".$TICKS_EVERY."d", $i);
			#}

			# seq1 ruler
			my $pos1 = $self->pdlindex($i, 0=>1);
			if ($pos1 !=0
			 and
			(my $abs1 = $self->_abs_pos($pos1, 1))  % $TICKS_EVERY == 0)
			{
				$seq1_ruler_bars .= '|';
				substr ($seq1_ruler, 1-length($abs1), length($abs1)) = $abs1;

			} else  {
				$seq1_ruler_bars .= " ";
				$seq1_ruler .= " ";
			}


			# identity bars with cutoff shading

			if ($self->conservation1->[$pos1] >= $self->cutoff
			and ($i == $blockstart
				 or $self->conservation1->[$pos1-1] < $self->cutoff))
			{
				$identity_bars .= '<SPAN style="background-color:#dfdfdf">' unless $span_open;
				$span_open= 1;
			}

			$identity_bars .= (
			($alnarray1[$i] eq $alnarray2[$i])
				? '|' : ' ');

			if ($self->conservation1->[$pos1] >= $self->cutoff
			and ($i == $blockstart+$BLOCK_WIDTH-1
				 or $self->conservation1->[$pos1+1] < $self->cutoff))
			{
				$identity_bars .= '</SPAN>'; $span_open = 0;
			}

			# note the sequence number of the most recent nucleotide

			#if (my $x = $self->pdlindex($i, 0 => 1)) { $lastindex1 = $x ;}
			#if (my $x = $self->pdlindex($i, 0 => 2)) { $lastindex2 = $x ;}


			# seq2 ruler
			my $pos2 = $self->pdlindex($i, 0=>2);
			if ($pos2 !=0
			and
			(my $abs2 = $self->_abs_pos($pos2, 2))  % $TICKS_EVERY == 0)
			{
				$seq2_ruler_bars .= '|';
				substr ($seq2_ruler, 1-length($abs2), length($abs2)) = $abs2;

			} else  {
				$seq2_ruler_bars .= " ";
				$seq2_ruler .= " ";
			}

		}

		print STDERR "FOR1 TIME:".(time - $START_TIME)."\n";

		if ($span_open) {$identity_bars .= '</SPAN>';} #dirty fix
		# the sites

		my (@site1strings, @site2strings, %url1, %url2);
		while ($site1
			   and
			   ((my $sitepos = $self->pdlindex($site1->start(), 1=>0))
			<
			   ( $blockstart + $BLOCK_WIDTH - $SITE_SHIFT)))  {

			my $strlen; my $is_free = 0; my $offset=0;
			if (defined $site1strings[$is_free]) {
				$strlen = length($site1strings[$is_free]);
			}
			else { $strlen=0; }
			$offset = ($sitepos+$SITE_SHIFT -($s%$BLOCK_WIDTH)) % $BLOCK_WIDTH; $offset++;
			while (($strlen
				>= $offset-1
				 )
			   and ($strlen > 0)
			   )
			{
			#print STDERR "CONTROL: OFFSET $offset SITEPOS $sitepos STRLEN $strlen \n";
			last if $strlen < 1;
			$is_free++; last if $offset <0;
			if ($is_free>100)  { # something is wrong then
				#print STDERR "DUMP:\n". Data::Dumper->Dump([@site1strings]);
				last;
			}
			if (defined $site1strings[$is_free]) {
				$strlen = length($site1strings[$is_free]);
			}
			else { $strlen=0; }

			}

			my $site_id;

			# pick an unused three-digit label for the site

			do
			{$site_id = sprintf("%03d", rand(1000))}
			while defined $url1{$site_id};
			#print STDERR "FACTOR NAME:".$site1->Matrix->{name}."\n";
			$site1strings[$is_free] .= (" "x($offset-$strlen-1)).
			$site_id.($site1->strand()=="-1"?"-":"+").$site1->siteseq().
			":".$site1->Matrix->{name};
			$site2strings[$is_free] .= (" "x($offset-$strlen-1)).
			$site_id.($site2->strand()=="-1"?"-":"+").$site2->siteseq().
			":".$site2->Matrix->{name};
			$url1{$site_id} = $self->site_url($site1, $site2, $site1);
			$url2{$site_id} = $self->site_url($site1, $site2, $site2);
			#print STDERR "SITE1:\n".Data::Dumper->Dump([$site1]);


			($site1 = $iterator1->next()) || last;
			($site2 = $iterator2->next()) || last;

		}
		print STDERR "WHILE1 TIME:".(time - $START_TIME)."\n";

		# print STDERR "NR. SITE1STRINGS: ".scalar(@site1strings)."\n";
		for (my $i=0; $i<scalar(@site1strings); $i++)  {
			#print STDERR "SITE1STRING: before:".$site1strings[$i]."\n";
			$site1strings[$i] =~ s/(\d{3})(\+|\-)\S+/$url1{$1} /g;
			#print STDERR "SITE1STRING: after:".$site1strings[$i]."\n";
			$site2strings[$i] =~ s/(\d{3})(\+|\-)\S+/$url2{$1} /g;
		}
		print STDERR "FOR2 TIME:".(time - $START_TIME)."\n";



		$outstring .= join
			("", hr,br,"&nbsp;\n",
			 (map {(" "x($TITLE_AREA + 4-$SITE_SHIFT). $_."\n")}
				  reverse(@site1strings)),
			 "$seq1_ruler\n",
			 sprintf("%".$TITLE_AREA."s    %-".$BLOCK_WIDTH."s  %s\n",
				 " ", $seq1_ruler_bars, " "),
			 sprintf("<I><B><FONT color=$seq1hex>%".$TITLE_AREA.
				 "s</FONT></B></I>    %-".$BLOCK_WIDTH."s  %s\n",
				 $self->seq1name(), $seq1slice, " "),
			 sprintf("%".$TITLE_AREA."s    %-".$BLOCK_WIDTH."s  %s\n",
				 "", $identity_bars, ""),
			 sprintf("<I><B><FONT color=$seq2hex>%".$TITLE_AREA.
				 "s</FONT></B></I>    %-".$BLOCK_WIDTH."s  %s\n",
				 $self->seq2name(), $seq2slice, " "),
			 sprintf("%".$TITLE_AREA."s    %-".$BLOCK_WIDTH."s  %s\n",
				 " ", $seq2_ruler_bars, " "),
			 "$seq2_ruler\n",
			 (map {(" "x($TITLE_AREA + 4-$SITE_SHIFT). $_."\n")} @site2strings),
			 "\n\n");
		$blockstart += $BLOCK_WIDTH;

		print STDERR "BLOCKSTART: $blockstart E $e E=>1 ".($self->pdlindex($e, 1=>0)-$BLOCK_WIDTH)."\n";

    } while ($blockstart <= $e);

	print STDERR "TOTAL TIME:".(time - $START_TIME)."\n";
    my $page_id = sprintf("%04d", int rand(10000));
    my $image = $self->_drawaln_png();
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".ALN.png");
    print OUT $image->png();
    close OUT;
	my $graphtable = table(Tr(td(img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".ALN.png"}))));


    return ($outstring, $graphtable);
}


sub site_url {

    my ($self, $site1, $site2, $site) = @_;
    	my $URL = $self->REL_CGI_BIN_DIR."/jaspartf?ID=".$site1->Matrix->{ID}.
	    "&score1=".$site1->score().
		"&score2=".$site2->score().
		    "&pos1=".$self->_abs_pos($site1->start(), 1).
			"&pos2=".$self->_abs_pos($site2->start(), 2).
			    "&seq1=".$self->seq1name().
				"&seq2=".$self->seq2name().
				    "&name=".$site1->Matrix->{name}.
				    "&jobID=".$self->{job}->jobID()."";

    my $url = b({-style=>"background-color:#dfdfdf"},_plussiteseq($site)).":".
	a({-href=>$self->REL_CGI_BIN_DIR."/jaspartf?ID=".$site->Matrix->{ID}.
	       "&jobID=".$self->{job}->jobID()."",
	   -onClick  =>
	       "window.open('$URL', 'TFprofile', ".
	       "'height=400,width=500,toolbar=no,menubar=no,".
		   "scrollbars=yes,resizable=yes'); return false;",

	   -onMouseOver=>
	       "status='TF: ".$site->Matrix->{name}. "; ".
	       "Structural class: ".$site->Matrix->{class}. "; ".
	       "Score ".$site->score()." (".
		   int(($site->score()-$site->Matrix->{min_score})/
		       ($site->Matrix->{max_score}-$site->Matrix->{min_score})
		       *100
		       +0.5).
	       "%)';",
		   -onMouseOut=>"status=''"},
	  $site->Matrix->{name}).
	"[".($site->strand()=="-1"?"-":"+")."]";
    return $url;

}


sub _plussiteseq  {

    # a utility function
    my $site = shift;
    if ($site->strand == -1)  {
	return Bio::Seq->new(-seq=>$site->siteseq,
			     -moltype=>'dna')->revcom->seq;
    }
    else {
	return $site->siteseq;
    }
}


sub maparea_factor  {
    my ($self, $which, $site, $site2, $x1, $y1, $x2, $y2) = @_;
    my $URL = $self->REL_CGI_BIN_DIR."/jaspartf?ID=".$site->Matrix->{ID}.
	"&score1=".$site->score().
	    "&score2=".$site2->score().
		"&pos1=".$self->_abs_pos($site->start(),$which).
		    "&pos2=".$self->_abs_pos($site2->start(), 3-$which).
			"&seq1=".$self->seq1name().
			    "&seq2=".$self->seq2name().
				"&name=".$site->Matrix->{name}.
				"&jobID=".$self->{job}->jobID()."";
    my $onClick = "window.open('$URL', 'TFprofile',
    'height=400,width=500,toolbar=no,menubar=no,scrollbars=yes,resizable=yes');
     return false;";
    my $onMouseOver = "TF: ".$site->Matrix->{name}. "; ".
	       "Structural class: ".$site->Matrix->{class}. "; ".
	       "Score ".$site->score()." (".
		   int(($site->score()-$site->Matrix->{min_score})/
		       ($site->Matrix->{max_score}-$site->Matrix->{min_score})
		       *100
		       +0.5).
			   "%)";
    return qq!<AREA COORDS="$x1,$y1,$x2,$y2"
	       SHAPE="RECT"
	       HREF="$URL"
	       TARGET="_blank"
	       ALT="$onMouseOver"
	       onMouseOver="status='$onMouseOver';"
	       onMouseOut="status=''"
	       ONCLICK="$onClick">!;

}


sub HTML_image  {
    my $self = shift;
    my $page_id = sprintf("%04d", int rand(10000));
    my ($image, $image1map) = $self->_drawgene_png();
    open (OUT,">".$self->ABS_TMP_DIR."/".$self->{job}->jobID().$page_id.".GENE1.png");
    print OUT $image->png();
    close OUT;
    my $image2map;
    ($image, $image2map) = $self->_drawgene_png(2);
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".GENE2.png");
    print OUT $image->png();
    close OUT;
    $image = $self->_drawpf_png(1);
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".PF1.png");
    print OUT $image->png();
    close OUT;
    $image = $self->_drawpf_png(2);
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".PF2.png");
    print OUT $image->png();
    close OUT;
    $image = $self->_drawaln_png();
    open (OUT,">".$self->ABS_TMP_DIR."/"
	  .$self->{job}->jobID().$page_id.".ALN.png");
    print OUT $image->png();
    close OUT;

    return table(Tr(td(img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".ALN.png"}))),
		 Tr(td({-align=>"center"},
		       hr,font({-size=>"+1"}, b("Conservation profile of ".
						font({-color=>$seq1hex},i($self->seq1name)))))),
		  Tr(td($image1map.
		       img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".GENE1.png",
			    -usemap=>"#seq1map", -border=>0}))),
		 Tr(td(img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".PF1.png"}))),
		 Tr(td({-align=>"center"},
		       hr,font({-size=>"+1"},
			       b("Conservation profile of ".
				 font({-color=>$seq2hex},i($self->seq2name)))))),
		 Tr(td($image2map.
		       img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".GENE2.png",
			    -usemap=>"#seq2map", -border=>0}))),
		 Tr(td(img({-src=>$self->REL_TMP_DIR."/".
				$self->{job}->jobID().$page_id.".PF2.png"}))));
}


sub _drawaln_png {
    my $self = shift;
    my $image_map_areas = "";

    # this is factor for the whole alignment: the denominator is the
    # entire length of the alignment

    my $factor = (IMAGE_WIDTH - 2*IMAGE_MARGIN)
	                        /
		 ($self->pdlindex->getdim(0));
    my $FONT = gdSmallFont;

    # create image

    my $OFFSET = IMAGE_MARGIN;# +(scalar(@labelrows)+2)*($FONT->height+$SPACING);
    my $im = GD::Image->new(IMAGE_WIDTH,
			    $OFFSET + 6*3 + IMAGE_MARGIN);
    my $lightgray = $im->colorAllocate(217,217,217);
    my $white = $im->colorAllocate(255,255,255);
    my $black = $im->colorAllocate(0,0,0);
    my $gray  = $im->colorAllocate(127,127,127);
    my $red   = $im->colorAllocate(255,0,0);
    my $blue  = $im->colorAllocate(0,0,255);
    my $lightred = $im->colorAllocate(255,127,127);
    my $lightyellow = $im->colorAllocate(255,255,127);
    my $yellow = $im->colorAllocate(255,255,0);
    my $seq1color = $im->colorAllocate(@seq1RGB);
    my $seq2color = $im->colorAllocate(@seq2RGB);


    # draw position box

    my ($s, $e) = ($self->start_at(),$self->end_at());
    $im->filledRectangle($s * $factor+IMAGE_MARGIN, 0, #$OFFSET-10,
			 $e * $factor+IMAGE_MARGIN, $OFFSET + 6*3 + IMAGE_MARGIN,#$OFFSET+25,
			 $white);

    # draw seq1

    my $pSeq1Pdl =
	$self->pdlindex->slice(':,0')->where
	    ($self->pdlindex->slice(':,1') > 0);
    $pSeq1Pdl = $pSeq1Pdl->where($pSeq1Pdl>0);
    my $pSeq1Starts =
	$pSeq1Pdl->slice('1:-1')->where(
	    ($pSeq1Pdl->slice('1:-1' )- $pSeq1Pdl->slice('0:-2')>1));
    my $pSeq1Ends =
	$pSeq1Pdl->slice('0:-2')->where(
	    ($pSeq1Pdl->slice('1:-1' )- $pSeq1Pdl->slice('0:-2')>1));
    my @seq1_starts = (list($pSeq1Pdl->slice(0)*$factor +IMAGE_MARGIN),
		       (list ($pSeq1Starts*$factor +IMAGE_MARGIN)));
    my @seq1_ends = ((list ($pSeq1Ends*$factor +IMAGE_MARGIN),
		      list($pSeq1Pdl->slice(-1)*$factor +IMAGE_MARGIN)));

    # numbers
    my ($abs1_start, $abs1_end) =
	($self->_abs_pos(1,1), $self->_abs_pos($self->seq1length, 1));
    $im->string(gdTinyFont, $seq1_starts[0] - gdTinyFont->width*length($abs1_start)/2,
		$OFFSET - (gdTinyFont->height),
		$abs1_start, $black);
    $im->string(gdTinyFont,
		$seq1_ends[-1] - gdTinyFont->width*length($abs1_end)/2,
		$OFFSET - (gdTinyFont ->height),
		$abs1_end, $black);
    while ( my $seq1start = splice (@seq1_starts, 0, 1))  {
	my $seq1end = splice (@seq1_ends, 0,1);
	$im->filledRectangle($seq1start, $OFFSET+2, $seq1end, $OFFSET+5, $seq1color);
    }


    # draw seq2
    my $pSeq2Pdl =
	$self->pdlindex->slice(':,0')->where
	    ($self->pdlindex->slice(':,2') > 0);
    $pSeq2Pdl = $pSeq2Pdl->where($pSeq2Pdl>0);

    my $pSeq2Starts =
	$pSeq2Pdl->slice('1:-1')->where(
	    ($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

    my $pSeq2Ends =
	$pSeq2Pdl->slice('0:-2')->where(
	    ($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

    my @seq2_starts = (list($pSeq2Pdl->slice(0)*$factor +IMAGE_MARGIN),
		       (list ($pSeq2Starts*$factor +IMAGE_MARGIN)));

    my @seq2_ends = ((list ($pSeq2Ends*$factor +IMAGE_MARGIN),
		      list($pSeq2Pdl->slice(-1)*$factor +IMAGE_MARGIN)));


    my ($abs2_start, $abs2_end) =
	($self->_abs_pos(1,2), $self->_abs_pos($self->seq2length, 2));
    $im->string(gdTinyFont, $seq2_starts[0] - gdTinyFont->width*length($abs2_start)/2,
		$OFFSET+19,
		$abs2_start, $black);
    $im->string(gdTinyFont,
		$seq2_ends[-1]- gdTinyFont->width*length($abs2_end)/2,
		$OFFSET+19,
		$abs2_end, $black);
    while ( my $seq2start = splice (@seq2_starts, 0, 1))  {
	my $seq2end = splice (@seq2_ends, 0,1);
	$im->filledRectangle($seq2start, $OFFSET+14, $seq2end,
			     $OFFSET+17, $seq2color);
    }

    # draw exons
    my @color = ($white, $lightyellow, $lightred);

    foreach my $which (1,2)  {
	my $curr_color = ($seq1color, $seq2color)[$which-1];
	my $curr_yoffset = ($OFFSET+2,$OFFSET+14)[$which-1];

	foreach my $exontype (1,2)  {
	    my $pExonPdl =
		$self->pdlindex->slice(":,0")->where
		    ($self->pdlindex->slice(":,3") == $exontype);
	    $pExonPdl = $pExonPdl->where($pExonPdl>0);
	    if ($pExonPdl->getdim(0) > 3) {

		my $pExonStarts =
		    $pExonPdl->slice('1:-1')->where
			(($pExonPdl->slice('1:-1' )- $pExonPdl->slice('0:-2')>1));

		my $pExonEnds =
		    $pExonPdl->slice('0:-2')->where
			(($pExonPdl->slice('1:-1' )- $pExonPdl->slice('0:-2')>1));

		my @abs_exon_starts = (list($pExonPdl->slice(0)),
				       list($pExonStarts));

		my @abs_exon_ends   = (list($pExonEnds),
				   list($pExonPdl->slice(-1)));

		my @exon_starts = ((list($factor*$pExonPdl->slice(0)
				     + IMAGE_MARGIN)),
			       (list ($pExonStarts*$factor +IMAGE_MARGIN)));
		my @exon_ends = ((list ($pExonEnds*$factor +IMAGE_MARGIN)),
				 (list($factor*$pExonPdl->slice(-1) +IMAGE_MARGIN)));


		while ( my $exonstart = splice (@exon_starts, 0, 1))  {
		    my $exonend = splice (@exon_ends, 0,1);

		    my $es = splice(@abs_exon_starts,0,1);
		    my $ee = splice(@abs_exon_ends,0,1);

                    # correct edges of $es and $ee
		    $es = $self->pdlindex($self->higher_pdlindex($es, 0=>$which), $which=>0);
		    $ee = $self->pdlindex($self->lower_pdlindex($ee, 0=>$which), $which=>0);

		    # this is just pasted here ... baaad
		    my $pSeq2Pdl =
			$self->pdlindex->slice("$es:$ee,0")->where
			    ($self->pdlindex->slice("$es:$ee,".($which)) > 0);

		    $pSeq2Pdl = $pSeq2Pdl->where($pSeq2Pdl>0);
		    if (1)  { #($pSeq2Pdl->getdim(0) >= 2)  {

			my $pSeq2Starts =
			    $pSeq2Pdl->slice('1:-1')->where
				(($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

			my $pSeq2Ends =
			    $pSeq2Pdl->slice('0:-2')->where
				(($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

			my @seq2_starts =
			    ($es*$factor +IMAGE_MARGIN,
			     (list (($pSeq2Starts)*$factor +IMAGE_MARGIN)));

			my @seq2_ends =
			    ((list (($pSeq2Ends)*$factor +IMAGE_MARGIN),
			      $ee*$factor +IMAGE_MARGIN));

			my ($the_start, $the_end) = ($seq2_starts[0], $seq2_ends[-1]);

			while ( my $seq2start = splice (@seq2_starts, 0, 1))  {
			    my $seq2end = splice (@seq2_ends, 0,1);

			    $im->filledRectangle($seq2start, $curr_yoffset-2,
						 $seq2end, $curr_yoffset+5, $color[$exontype]);
			    $im->line($seq2start, $curr_yoffset-2,
					     $seq2end, $curr_yoffset-2, $curr_color);
			    $im->line($seq2start, $curr_yoffset+5,
				      $seq2end, $curr_yoffset+5, $curr_color);
			}

			my $left_edge = ($es==0 or !$self->pdlindex->at($es-1, 3));
			my $right_edge = ($ee>=($self->pdlindex->getdim(0)-1) or !$self->pdlindex->at($ee+1, 3));

			$im->line($the_start, $curr_yoffset-2,
				  $the_start, $curr_yoffset+5, $curr_color) if $left_edge;
			$im->line($the_end, $curr_yoffset-2,
				  $the_end, $curr_yoffset+5, $curr_color) if $right_edge;
		    }
		}
	    }
	}
    }


    # draw labels for the sequences

    $im->string(gdTinyFont,
		IMAGE_MARGIN -
		     (length($self->seq1name())+1)* gdTinyFont->width,
		$OFFSET-1,
		$self->seq1name(), $black);

    $im->string(gdTinyFont,
		IMAGE_MARGIN -
		     (length($self->seq2name())+1) * gdTinyFont->width,
		$OFFSET+9,
		$self->seq2name(), $black);

    return $im;


}


sub _drawgene_png  {

    my ($self, $which)  = @_;
    $which or $which=1;
    my $image_map_areas = "";
    my $FONT = gdSmallFont;
    my ($s, $e, $BEGIN_AT, $END_AT, $ref_site_iterator, $other_site_iterator,
	$ref_seq_color, $other_seq_color, $ref_seq_yoffset, $other_seq_yoffset);
    my $SPACING = 1; #vertical spacing between labels

    # set parameters and draw

    if ($which == 2)  {
	$BEGIN_AT = $self->higher_pdlindex($self->start_at(), 0=>2);
	$END_AT   = $self->lower_pdlindex($self->end_at(),   0=>2);
	$ref_site_iterator = $self->fsiteset2->Iterator(-sort_by =>'start',
							-reverse =>1);
	$other_site_iterator = $self->fsiteset1->Iterator(-sort_by =>'start',
							  -reverse =>1);

    }

    else  {
	$BEGIN_AT = $self->higher_pdlindex($self->start_at(), 0=>1);
	$END_AT   = $self->lower_pdlindex($self->end_at(),   0=>1);
	($s, $e) = ($self->start_at(), $self->end_at());
	$ref_site_iterator = $self->fsiteset1->Iterator(-sort_by =>'start',
							-reverse =>1);
	$other_site_iterator = $self->fsiteset2->Iterator(-sort_by =>'start',
							-reverse =>1);
	$which = 1;
    }

    my $factor = (IMAGE_WIDTH - 2*IMAGE_MARGIN)
	                        /
		 ($END_AT-$BEGIN_AT +1);

    my @labelrows;
    my ($leftmostpos, $leftmostrow);
    my @leftmostpos_in_row; # for labels
    while (my $site = $ref_site_iterator->next())  {
	my $site2 = $other_site_iterator->next();
	next if $site->end > $END_AT;
	last if $site->start< $BEGIN_AT;
	my $xpos = ($site->start() - $BEGIN_AT) * $factor + IMAGE_MARGIN;
	my $row=0;
	while ($labelrows[$row]
	       and
	       (($xpos + (length($site->Matrix->{name}) +1) * $FONT->width)
	       >
	       $leftmostpos )#$labelrows[$row][0]->{pos}))
	       and
	       (($xpos + (length($site->Matrix->{name}) +1) * $FONT->width)
	       >
	       $leftmostpos_in_row[$row]))
	       #and
	       #($row<=$leftmostrow))
	{
	    $row++;
	}
	for my $i (0..$row) {$leftmostpos_in_row[$i] = $xpos;}
	($leftmostpos, $leftmostrow) = ($xpos, $row);
	unshift @{$labelrows[$row]}, {pos => $xpos, site => $site, site2 =>$site2};
    }

    # create image

    my $OFFSET = IMAGE_MARGIN/4 +(scalar(@labelrows)+2)*($FONT->height+$SPACING);
    my $im = GD::Image->new(IMAGE_WIDTH,
			    $OFFSET + 6*3 + IMAGE_MARGIN/2);
    my $white = $im->colorAllocate(255,255,255);
    my $black = $im->colorAllocate(0,0,0);
    my $gray  = $im->colorAllocate(127,127,127);
    my $red   = $im->colorAllocate(255,0,0);
    my $blue  = $im->colorAllocate(0,0,255);
    my $yellow      = $im->colorAllocate(200,200,0);
    my $lightyellow = $im->colorAllocate(255,255,127);
    my $lightred = $im->colorAllocate(255,127,127);
    my $seq1color = $im->colorAllocate(@seq1RGB);
    my $seq2color = $im->colorAllocate(@seq2RGB);

    if ($which == 2)  {
	($ref_seq_color, $other_seq_color) = ($seq2color, $seq1color);
	($ref_seq_yoffset, $other_seq_yoffset) = ($OFFSET+14, $OFFSET+2);
    }
    else  {
	($ref_seq_yoffset, $other_seq_yoffset) = ($OFFSET+2, $OFFSET+14);
	($ref_seq_color, $other_seq_color) = ($seq1color, $seq2color);

    }

    # alignment positions of $self->start and $self->end

    ($s, $e) = ($self->pdlindex($BEGIN_AT, $which=>0),
		   $self->pdlindex($END_AT,   $which=>0));

    # draw seq2

    my $pSeq2Pdl =
	$self->pdlindex->slice("$s:$e,$which")->where
	    ($self->pdlindex->slice("$s:$e,".(3-$which)) > 0);

    my ($seq2_start, $seq2_end);

    $pSeq2Pdl = $pSeq2Pdl->where($pSeq2Pdl>0);
    if (1)  { #($pSeq2Pdl->getdim(0) >= 2)  {

	my $pSeq2Starts =
	    $pSeq2Pdl->slice('2:-1')->where
		(($pSeq2Pdl->slice('2:-1' )- $pSeq2Pdl->slice('1:-2')>1));

	my $pSeq2Ends =
	    $pSeq2Pdl->slice('1:-2')->where
		(($pSeq2Pdl->slice('2:-1' )- $pSeq2Pdl->slice('1:-2')>1));

	my @seq2_starts =
	    (($pSeq2Pdl->at(0)-$BEGIN_AT)*$factor +IMAGE_MARGIN,
	     (list (($pSeq2Starts-$BEGIN_AT)*$factor +IMAGE_MARGIN)));

	my @seq2_ends =
	    ((list (($pSeq2Ends-$BEGIN_AT)*$factor +IMAGE_MARGIN),
	      list(($pSeq2Pdl->slice(-1)-$BEGIN_AT)*$factor +IMAGE_MARGIN)));

	$seq2_start = $seq2_starts[0];
	$seq2_end   = $seq2_ends[-1];

	while ( my $seq2start = splice (@seq2_starts, 0, 1))  {
	    my $seq2end = splice (@seq2_ends, 0,1);
	    $im->filledRectangle($seq2start, $other_seq_yoffset,
			     $seq2end, $other_seq_yoffset+3, $other_seq_color);
	}
    }


    # reference sequence (continuous)

    $im->filledRectangle(IMAGE_MARGIN, $ref_seq_yoffset,
			 IMAGE_WIDTH - IMAGE_MARGIN -1, $ref_seq_yoffset +3,
			 $ref_seq_color);

    # draw exons

    my @ref_exon_params; # remember now, draw later

    foreach my $exontype (1,2)  {
	my $pExonPdl =
	    $self->pdlindex->slice("$s:$e,$which")->where
		($self->pdlindex->slice("$s:$e,3") == $exontype);
	$pExonPdl = $pExonPdl->where($pExonPdl>0);
	if ($pExonPdl->getdim(0) > 3) {

	    my $pExonStarts =
		$pExonPdl->slice('1:-1')->where
		    (($pExonPdl->slice('1:-1' )- $pExonPdl->slice('0:-2')>1));

	    my $pExonEnds =
		$pExonPdl->slice('0:-2')->where
		    (($pExonPdl->slice('1:-1' )- $pExonPdl->slice('0:-2')>1));

	    my @abs_exon_starts = (list($pExonPdl->slice(0)),
				   list($pExonStarts));

	    my @abs_exon_ends   = (list($pExonEnds),
				   list($pExonPdl->slice(-1)));
	    my $left_edge = ($s==0 or !$self->pdlindex->at($s-1, 3));
	    my $right_edge = ($e>=($self->pdlindex->getdim(0)-1) or !$self->pdlindex->at($e+1, 3));

	    my @exon_starts =
		((list($factor*($pExonPdl->slice(0)-$BEGIN_AT) +IMAGE_MARGIN)),
		 (list (($pExonStarts-$BEGIN_AT)*$factor +IMAGE_MARGIN)));

	    my @exon_ends =
		((list (($pExonEnds-$BEGIN_AT)*$factor +IMAGE_MARGIN)),
		 (list($factor*($pExonPdl->slice(-1)-$BEGIN_AT) +IMAGE_MARGIN)));

	    while ( my $exonstart = splice (@exon_starts, 0, 1))  {
		my $exonend = splice (@exon_ends, 0,1);

		push @ref_exon_params, [$exonstart, $ref_seq_yoffset-2,
					$exonend, $ref_seq_yoffset+5,
					($lightyellow, $lightred)[$exontype-1]],
				       [$exonstart, $ref_seq_yoffset-2,
					$exonend, $ref_seq_yoffset-2,
					$ref_seq_color],
				       [$exonstart, $ref_seq_yoffset+5,
					$exonend, $ref_seq_yoffset+5,
					$ref_seq_color],
				       $left_edge ? [$exonstart, $ref_seq_yoffset-2 ,
					$exonstart, $ref_seq_yoffset+5,
					$ref_seq_color] : 0,
				       $right_edge ? [$exonstart, $ref_seq_yoffset-2,
					$exonstart, $ref_seq_yoffset+5,
					$ref_seq_color] :0
					;

		my $es = $self->pdlindex(splice(@abs_exon_starts,0,1), $which=>0);
		my $ee = $self->pdlindex(splice(@abs_exon_ends,0,1),   $which=>0);

		# correct for truncation
		$es = $self->pdlindex($self->higher_pdlindex($es, 0=>(3-$which)), (3-$which)=>0);
		$ee = $self->pdlindex($self->lower_pdlindex($ee, 0=>(3-$which)), (3-$which)=>0);

		# this is just pasted here ... baaad

		my $pSeq2Pdl =
		    $self->pdlindex->slice("$es:$ee,$which")->where
			($self->pdlindex->slice("$es:$ee,".(3-$which)) > 0);

		$pSeq2Pdl = $pSeq2Pdl->where($pSeq2Pdl>0);
		if (1)  { #($pSeq2Pdl->getdim(0) >= 2)  {

		    my $pSeq2Starts =
			$pSeq2Pdl->slice('1:-1')->where
			    (($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

		    my $pSeq2Ends =
			$pSeq2Pdl->slice('0:-2')->where
			    (($pSeq2Pdl->slice('1:-1' )- $pSeq2Pdl->slice('0:-2')>1));

		    my @abs_exon_starts = (list($pExonPdl->slice(0)),
				   list($pExonStarts));

		    my @abs_exon_ends   = (list($pExonEnds),
					   list($pExonPdl->slice(-1)));

		    my $left_edge = ($es==0 or !$self->pdlindex->at($es-1, 3));
		    my $right_edge = ($ee>=($self->pdlindex->getdim(0)-1) or !$self->pdlindex->at($ee+1, 3));



		    my @seq2_starts =
			(($self->pdlindex($es,0=>$which)-$BEGIN_AT)*$factor +IMAGE_MARGIN,
			 (list (($pSeq2Starts-$BEGIN_AT)*$factor +IMAGE_MARGIN)));

		    my @seq2_ends =
			((list (($pSeq2Ends-$BEGIN_AT)*$factor +IMAGE_MARGIN),
			  ($self->pdlindex($ee, 0=>$which)-$BEGIN_AT)*$factor +IMAGE_MARGIN));

		    my ($the_start, $the_end) = ($seq2_starts[0], $seq2_ends[-1]);

		    while ( my $seq2start = splice (@seq2_starts, 0, 1))  {
			my $seq2end = splice (@seq2_ends, 0,1);

			$im->filledRectangle($seq2start, $other_seq_yoffset-2,
					     $seq2end, $other_seq_yoffset+5, $lightyellow);
			$im->line($seq2start, $other_seq_yoffset-2,
					     $seq2end, $other_seq_yoffset-2, $other_seq_color);
			$im->line($seq2start, $other_seq_yoffset+5,
					     $seq2end, $other_seq_yoffset+5, $other_seq_color);
		    }
		    # draw the vertical lines if edges
		    $im->line($the_start, $other_seq_yoffset-2,
			      $the_start, $other_seq_yoffset+5, $other_seq_color) if $left_edge;
		    $im->line($the_end, $other_seq_yoffset-2,
			      $the_end, $other_seq_yoffset+5, $other_seq_color) if $right_edge;
		}
	    }
	}
    }

    # The endpoint and numbers on the sequence

    my $ref_start = $self->higher_pdlindex($s, 0 => $which);
    my $ref_end   = $self->lower_pdlindex ($e, 0 => $which);
    my $other_start = $self->higher_pdlindex($s, 0 => 3-$which);
    my $other_end   = $self->lower_pdlindex ($e, 0 => 3-$which);

    my @letter_yoffset = ($OFFSET-1 - gdTinyFont->height, $OFFSET+21);

    $im->string(gdTinyFont, IMAGE_MARGIN - gdTinyFont->width*length($ref_start)/2,
		$letter_yoffset[$which-1],
		$ref_start,
		$black);
    $im->string(gdTinyFont, IMAGE_WIDTH - IMAGE_MARGIN - gdTinyFont->width*length($ref_end)/2,
		$letter_yoffset[$which-1],
		$ref_end,
		$black);
    $im->string(gdTinyFont, $seq2_start - gdTinyFont->width*length($other_start)/2,
		$letter_yoffset[2-$which],
		$other_start,
		$gray);
    $im->string(gdTinyFont, $seq2_end - gdTinyFont->width*length($other_end)/2,
		$letter_yoffset[2-$which],
		$other_end,
		$gray);


    # put the labels

    foreach my $row(0..$#labelrows)  {
	# line corner y value:
	my $lcy = $OFFSET - ($row+1.5)*($FONT->height()+$SPACING);
	# label y coordinate:
	my $laby = $OFFSET - ($row+2)*($FONT->height()+$SPACING);
	foreach my $label (@{$labelrows[$row]})  {

	    $im->line($label->{pos}, $ref_seq_yoffset-1,
		      $label->{pos}, $lcy,
		      $gray);
	    $im->line($label->{pos}, $lcy,
		      $label->{pos} + $FONT->width()/2-1, $lcy,
		      $gray);
	    my $name = $label->{site}->Matrix->{name};
	    $im->string($FONT, $label->{pos} + $FONT->width() -1, $laby,
			$name, $blue);
	    $image_map_areas .= $self->maparea_factor( $which, $label->{site}, $label->{site2},
				     $label->{pos}+$FONT->width() -1,
				     $laby,
				     $label->{pos}+$FONT->width()*(length($name)+1)-1,
				     $laby+$FONT->height());
	}
    }

    # draw the reference seq exons
    while (my ($filled_rect_params, $up_hor_par, $lo_hor_par, $l_vert_par, $r_vert_par) = splice(@ref_exon_params,0,5))  {

	$im->filledRectangle(@$filled_rect_params);
	$im->line(@$up_hor_par);
	$im->line(@$lo_hor_par);
	$im->line(@$l_vert_par) if $l_vert_par;
	$im->line(@$r_vert_par) if $r_vert_par;
    }




    return ($im, "<MAP name='seq".$which."map'> $image_map_areas </MAP>");

}

sub _drawpf_png  {
    my ($self, $which) = @_;
    my ($XDIM, $YDIM, $XOFFSET ,$YOFFSET) =
	(IMAGE_WIDTH, 250, IMAGE_MARGIN, 210);
    my $FONT = gdSmallFont;
    my $WINDOW = $self->window();
    my $CUTOFF = $self->cutoff();

    # the default settings are for seq1

    my $BEGIN_AT = $self->higher_pdlindex($self->start_at(), 0=>1);
    my $END_AT   = $self->lower_pdlindex($self->end_at(),   0=>1);
    my $STRAND   = 1;
    my @CONSERVATION = @{$self->conservation1()};

    my $factor = (IMAGE_WIDTH - 2*IMAGE_MARGIN)
	                        /
		   ($END_AT-$BEGIN_AT +1);


    # the following settings get rewritten if we are to
    # draw the profile for seq2

    if ($which == 2)  {
	$BEGIN_AT = $self->higher_pdlindex($self->start_at(), 0=>2);
	$END_AT   = $self->lower_pdlindex($self->end_at(),   0=>2);
	$STRAND   = $self->{job}->strand2;

	@CONSERVATION = @{$self->conservation2()};
	$factor = (IMAGE_WIDTH - 2*IMAGE_MARGIN)
	                        /
		   ($END_AT-$BEGIN_AT +1);
    }
    else  {
	$which=1;
    }

    my $image = new GD::Image(IMAGE_WIDTH, $YDIM);

    my $white       = $image->colorAllocate(255,255,255);
    my $black       = $image->colorAllocate(0,0,0);
    my $red         = $image->colorAllocate(255,0,0);
    my $yellow      = $image->colorAllocate(200,200,0);
    my $lightyellow = $image->colorAllocate(255,255,127);
    my $lightred  = $image->colorAllocate(255,180,180);
    my $green       = $image->colorAllocate(0,200,0);
    my $ltgray      = $image->colorAllocate(200,200,200);

    my $i=0;
    my ($abs_begin, $abs_end) =
	($self->_abs_pos($BEGIN_AT, $which), $self->_abs_pos($END_AT, $which));

    my @graphslice = @CONSERVATION[$BEGIN_AT..$END_AT];
    my @isexon     = (list $self->pdlindex->slice(':,3')->where($self->pdlindex->slice(":,$which")>0))[$BEGIN_AT..$END_AT];

    $image->string($FONT,
		   ($XOFFSET-length($abs_begin)*$FONT->width/2),
		   $YOFFSET+$FONT->height(),
		   $abs_begin, $black);
    $image->string($FONT,
		   ($XDIM-$XOFFSET-length($abs_end)*$FONT->width/2),
		   $YOFFSET+$FONT->height(),
		   $abs_end, $black);
    $image->string($FONT,
		   ($XOFFSET+$XDIM/2-18*$FONT->width),
		   $YOFFSET+$FONT->height(),
		   "nucleotide position", $black);
    my ($prev_x, $prev_y);
    foreach $i (0..$#graphslice){

	$image->line ($XOFFSET+$factor*$i, $YOFFSET,
		      $XOFFSET+$factor*$i, 2, (($lightyellow, $lightred)[$isexon[$i]-1]))
	    if $isexon[$i] and  int($XOFFSET+$factor*$i)!=int($prev_x) ;
	if (defined $prev_x) {
	    $image->line ($prev_x, $prev_y, ($XOFFSET+$factor*$i),
			  ($YOFFSET-(($YOFFSET-2)/100)*$graphslice[$i]),$red);
	}
	($prev_x, $prev_y) = ($XOFFSET+$factor*$i,
			      $YOFFSET-(($YOFFSET-2)/100)*$graphslice[$i]);
    }

    ##############
    # Draw the grid

    my $step = (int($STRAND*($abs_end-$abs_begin)/1000)*100 or 100);
    my $firstoffset=($STRAND==1
		     ? ($step - ($abs_begin % $step))
		     :($abs_begin % $step));


    for ($i=$firstoffset; $i< $STRAND*($abs_end-$abs_begin)- $FONT->width; $i+=$step)  {
	my $xpos=$XOFFSET + $i*$factor;
	$image->dashedLine($xpos, $YOFFSET, $xpos, 0, $ltgray);
	$image->stringUp($FONT, $xpos, $YOFFSET-10,
			 int($abs_begin+$i*$STRAND), $black);
    # print join ("\t",($xpos, $YOFFSET, $xpos, 0, "LINE")), "\n";
    }

    #############
    # Draw the  cutoff
    $image->dashedLine($XOFFSET, (1-$CUTOFF/100)*$YOFFSET,
		       $XDIM-$XOFFSET, (1-$CUTOFF/100)*$YOFFSET, $ltgray);
    #############
    # Draw the  cutoff labels
    $image->string($FONT,
		   $XOFFSET-(length(int($CUTOFF).""))*$FONT->width -3,
		   (1-$CUTOFF/100)*$YOFFSET-$FONT->height/2,
		   int($CUTOFF), $black);
    $image->string($FONT,
		   $XOFFSET-3*$FONT->width -3,
		   -4, #(1-$CUTOFF/100)*$YOFFSET-$FONT->height/2,
		   100, $black);
    $image->string($FONT,
		   $XOFFSET-$FONT->width -3,
		   $YOFFSET-6, #(1-$CUTOFF/100)*$YOFFSET-$FONT->height/2,
		   0, $black);

   $image->stringUp($FONT,
		   $XOFFSET-(3+length(int($CUTOFF).""))*$FONT->width -3,
		   $YOFFSET/2+$FONT->width*8,
		   "conservation (%)", $black);



    ###########
    # Draw rectangle around graph

    $image->filledRectangle($XOFFSET-1, $YOFFSET,
			    $XOFFSET, $YOFFSET+3, $black);
    $image->filledRectangle($XDIM-$XOFFSET, $YOFFSET,
			    $XDIM - $XOFFSET + 1, $YOFFSET+3, $black);
    $image->rectangle($XOFFSET, $YOFFSET, $XDIM-$XOFFSET, 1, $black);
    $image->rectangle($XOFFSET-1, $YOFFSET+1, $XDIM-$XOFFSET+1, 0, $black);

    return $image;

}

sub _parse_alignment {
    my ($self, $alignment, $format) = (@_, "clustalw");

    my ($seq1, $seq2, $start);

    my @match;
    #my @alnlines = split("\n", $alignment);
    #shift @alnlines;shift @alnlines;shift @alnlines; # drop header

    #while ($_=shift @alnlines) {
	#$start=1;
	# print $_;
	#my ($label1, $string1) = split; # (/\s+/($_, 21,60);
	#$self->seq1name($label1) unless $self->seq1name();
  	#my ($label2, $string2) = split /\s+/, shift(@alnlines);
 	#$self->seq2name($label2) unless $self->seq2name();
                     #substr($string2,21,60);
	#shift @alnlines; shift @alnlines; # skip asterisk line and blank line
	#$seq1 .= $string1;
	#$seq2 .= $string2;
    #}

    my $fh = IO::String->new($alignment);
    my $alnIO = Bio::AlignIO->new(-fh=>$fh,-format=>$format);
    my $alnobj = $alnIO->next_aln;
    $alnIO->close;

    my ($seqobj1, $seqobj2) = $alnobj->each_seq;
    my $seqstring1 = $seqobj1->seq; $seqstring1 =~ s/\W/\-/g;
    my $seqstring2 = $seqobj2->seq; $seqstring2 =~ s/\W/\-/g;

    $self->alignseq1($seqstring1);
    $self->seq1name($seqobj1->display_id) unless $self->seq1name;
    $self->alignseq2($seqstring2);
    $self->seq2name($seqobj2->display_id) unless $self->seq2name;
    $self->alignseq1array( my @seq1 = ("-", split('', $seqstring1) ));
    $self->alignseq2array( my @seq2 = ("-", split('', $seqstring2) ));

    my (@seq1index, @seq2index);
    my ($i1, $i2) = (0, 0);
    for (0..$#seq1) {
	my ($s1, $s2) = (0, 0);
	$seq1[$_] ne "-" and  $s1 = ++$i1;
	$seq2[$_] ne "-" and  $s2 = ++$i2;
	push @seq1index, $s1;
	push @seq2index, $s2;
    }

    $self->pdlindex( pdl [ [list sequence($#seq1+1)], [@seq1index], [@seq2index], [list zeroes ($#seq1+1)] ]) ;

    # mark exons in row 3
    my $seqobj =$self->{job}->seq1();
    my @features = $seqobj->top_SeqFeatures;
    for my $exon (@features)  {
	next unless ref($exon) =~ /::Exon/;
	my $exonstart = $self->pdlindex($exon->start(), 1=>0);
	my $exonend   = $self->pdlindex($exon->end(),   1=>0);

	my $sl = $self->pdlindex->slice("$exonstart:$exonend,3");
	$sl++;
    }

    # mark ORF

    my @cdnafeatures = ();
    if ($self->{job}->seq3())  {
	@cdnafeatures = $self->{job}->seq3()->top_SeqFeatures;
    }
    my ($cdnaexonstart, $cdnaexonend) = (0,0);
    my $orf;
    for my $feat (@cdnafeatures)  {
	if ((ref($feat) eq "Bio::SeqFeature::Generic"
		and $feat->primary_tag eq 'orf'))
	{
	    $orf = $feat;
	}
	elsif (ref($feat) =~ /::Exon/)  {
	    print STDERR "FIXING EXON: ".$feat->start."-".$feat->end."\n";
	    $cdnaexonstart = $feat->start() if $cdnaexonstart > $feat->start();
	    $cdnaexonend   = $feat->end()   if $cdnaexonend   < $feat->end();
	}
    }
    if ($orf)  {
	my ($orf_start, $orf_end, $orf_strand) =
	    ($orf->start(), $orf->end(), $orf->strand());
	print STDERR "PDL0 $cdnaexonstart $orf_start $orf_end $cdnaexonend\n";
	#if ($orf_start> $orf_end) {
	#    ($orf_start, $orf_end) = ($orf_end, $orf_start);
	#}
	print STDERR "PDL1\n";
	my $cdnaPdl =
	    $self->pdlindex->slice(':,3')->where
		($self->pdlindex->slice(':,3')==1);
	my $orfPdl;

	$orf_end = $cdnaexonend if $orf_end>$cdnaexonend;
	$orf_start = $cdnaexonstart if $orf_start < $cdnaexonstart;
	if ($orf_start<$orf_end)  {
	    if ($orf_strand eq "1") {
		$orf_end = $cdnaexonend if $orf_end>$cdnaexonend;
		print STDERR "PDL2 $cdnaexonstart $orf_start $orf_end $cdnaexonend\n";
		print STDERR "PDL slice:".(list($cdnaPdl));
		#$orfPdl = $cdnaPdl->slice
		 #   (($orf_start-$cdnaexonstart).":".($orf_end-$cdnaexonstart-1));
		$orfPdl = $self->pdlindex->slice(':,3')->slice
		    (($orf_start-$cdnaexonstart).":".($orf_end-$cdnaexonstart-1));
		$orfPdl = $orfPdl->where($orfPdl==1);
	    }
	    else  {
		print STDERR "PDL3\n";
		$orfPdl = $cdnaPdl->slice
		    (($self->{job}->seq3->length() - $orf_end + $cdnaexonstart).":".($self->{job}->seq3->length()-$orf_start+$cdnaexonstart-1));
	    }
	    #$orfPdl = $orfPdl+1;
	    $orfPdl .= 2;
	    print STDERR "CDNA:". list($cdnaPdl);
	}
	print STDERR "PDL4\n";

    }

    return 1;

}

sub pdlindex {
    my ($self, $input, $p1, $p2) = @_ ;

    if (ref($input) eq "PDL")  {
	$self->{pdlindex} = $input;
    }

    unless (defined $p2)  {
	return $self->{pdlindex};
    }
    else {
	my $interim_pdl =  $self->{pdlindex}->xchg(0,1)->slice($p2)->where
	    ( $self->{pdlindex}->xchg(0,1)->slice($p1)==$input);
	my @results = list($interim_pdl) if defined $interim_pdl;

	wantarray ? return @results : return $results[0];
    }
}

sub lower_pdlindex {
    my ($self, $input, $p1, $p2) = @_;
    unless (defined $p2)  {
	$self->throw("Wrong number of parameters passed to lower_pdlindex");
    }
    my $result;
    my $i = $input;

    until ($result = $self->pdlindex($i, $p1 => $p2))  {
	$i--;

	last if $i==0;
    }
    return $result or 1;
}

sub higher_pdlindex {
    my ($self, $input, $p1, $p2) = @_;
    unless (defined $p2)  {
	$self->throw("Wrong number of parameters passed to lower_pdlindex");
    }
    my $result;
    my $i = $input;
    until ($result = $self->pdlindex($i, $p1 => $p2))  {
	$i++;
	last unless ($self->pdlindex($i, $p1=>0) > 0);
    }
    return $result;
}


sub _calculate_conservation  {
    my ($self, $WINDOW, $which) = @_;
    my (@seq1, @seq2);
    if ($which==2)  {
	@seq1 = $self->alignseq2array();
	@seq2 = $self->alignseq1array();
    }
    else  {
	@seq1 = $self->alignseq1array();
	@seq2 = $self->alignseq2array();
	$which=1;
    }

    my @CONSERVATION;
    my @match;

    while ($seq1[0] eq "-")  {
	shift @seq1;
	shift @seq2;
    }

    for my $i (0..$#seq1) {
  	push (@match,( uc($seq1[$i]) eq uc($seq2[$i]) ? 1:0))
  	    unless ($seq1[$i] eq "-" or $seq1[$i] eq ".");
    }
    my @graph=($match[0]);
    for my $i (1..($#match+$WINDOW/2))  {
  	$graph[$i] = $graph[$i-1]
  	           + ($i>$#match ? 0: $match[$i])
  		   - ($i<$WINDOW ? 0: $match[$i-$WINDOW]);
    }

    # at this point, the graph values are shifted $WINDOW/2 to the right
    # i.e. the score at a certain position is the score of the window
    # UPSTREAM of it: To fix it, we shoud discard the first $WINDOW/2 scores:
    #$self->conservation1 ([]);
    foreach (@graph[int($WINDOW/2)..$#graph])  {
	push @CONSERVATION, 100*$_/$WINDOW;
    }

    return [@CONSERVATION];

}


sub _strip_gaps {
    # not OO
    my $seq = shift;
    $seq =~ s/\-|\.//g;
    return $seq;
}


sub _do_sitesearch  {
     my ($self, $MATRIXSET, $THRESHOLD, $CUTOFF) = @_;

    my $seqobj1 = Bio::Seq->new(-seq=>_strip_gaps($self->alignseq1()),
				-id => "Seq1");
    my $siteset1 =
	$MATRIXSET->search_seq(-seqobj => $seqobj1,
			    -threshold => $THRESHOLD);
#    $siteset1->sort();

    my $seqobj2 = Bio::Seq->new(-seq=>_strip_gaps($self->alignseq2()),
				-id => "Seq2");
    my $siteset2 =
	$MATRIXSET->search_seq(-seqobj => $seqobj2,
			    -threshold => $THRESHOLD);
#    $siteset2->sort();

    # instead of $comp_of_main($i) use $self->pdlindex($i, 1 => 2)
    # instead of @main_sites[0,1,2], use $siteset1 object
    # instead of @comp_sites, use $siteset2 object

#    $self->siteset1->reset();
 #   $self->fsiteset2->reset();
    my $iterator1 = $siteset1->Iterator(-sort_by=>'start');
    my $iterator2 = $siteset2->Iterator(-sort_by=>'start');
    my $site1 = $iterator1->next();
    my $site2 = $iterator2->next();

    # initialize filtered sitesets:

    $self->fsiteset1 (TFBS::SiteSet->new());
    $self->fsiteset2 (TFBS::SiteSet->new());

    while (defined $site1 and defined $site2) {
	my $pos1_in_aln = $self->pdlindex($site1->start, 1=>0);
	my $pos2_in_aln = $self->pdlindex($site2->start, 2=>0);
	my $cmp = (($pos1_in_aln <=> $pos2_in_aln)
		   or
		   ($site1->Matrix->name cmp $site2->Matrix->name));

	if ($cmp==0) { ### match
	    if (# threshold test:
		$self->conservation1->[$site1->start]
		>=
		$self->cutoff()
		and
		# exclude ORF test
		(!($self->{job}->exclude_orf()
		   and $self->pdlindex($site1->start(), 1=>3) == 2
		   )
		 )
		)
	    {
		$self->fsiteset1->add_site($site1);
		$self->fsiteset2->add_site($site2);
	    }
	    $site1 = $iterator1->next();
	    $site2 = $iterator2->next();
	}
	elsif ($cmp<0)  { ### $siteset1 is behind
	    $site1 = $iterator1->next();
	}
	elsif ($cmp>0)  { ### $siteset2 is behind
	    $site2 = $iterator2->next();
	}
    }
}

sub _abs_pos  {
    # this is ugly, but I have no time to make it better

    my ($self, $pos, $seqnr) = @_;
    no strict 'refs';
    my ($strand, $seqobj) = ("strand$seqnr", "seq$seqnr");
    if ($self->{job}->$strand eq "-1")  {
	return $self->{job}->$seqobj->length() - $pos  +1;
    }
    else  {
	return $pos;
    }

}

sub _abs_sign  {
    # this is also ugly, but I have no time to make it better

    my ($self, $sign, $seqnr) = @_;
    no strict 'refs';
    my $strand = "strand$seqnr";

    if ($self->{job}->$strand eq "-")  {
	return ($sign eq '-') ? "+" : "-";
    }
    else  {
	return $sign;
    }

}


sub _calculate_cutoff  {
    my ($self) = @_;
    my $ile = 0.9;
    my @conservation_array = sort {$a <=> $b} @{$self->conservation1()};

    my $perc_90 = $conservation_array[int($ile*scalar(@conservation_array))];
    return $perc_90;
}

1;




