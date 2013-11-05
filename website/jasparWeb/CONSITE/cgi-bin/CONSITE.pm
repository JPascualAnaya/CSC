package CONSITE_Interface;
my $DEBUG = 0;


#################################################################
# CHANGES
#
# 2001-05-25 Added relative (90-th parcentile) cutoff to analyses
#
#################################################################

use base 'CGI::Application';
use CONSITE_OPT;
use lib CONSITE_PERLLIB;

use CGI qw(Tr table td header);
use CGI::Carp qw(carpout);# fatalsToBrowser);
    open (LOG, ">".LOG_DIR."/CONSITE.errorlog") 
       or die "Could not open log file.";
    carpout(LOG);

use strict;

use DBI;
use LWP::UserAgent;
use HTTP::Request::Common;
use Persistence::Object::Simple;
use File::Temp qw(tempfile);
use CONSITE::Job;
use CONSITE::Alignment;
use CONSITE::SingleSeq;
use CONSITE::TFpicker;
use CONSITE::UserMatrix;
use TFBS::DB::JASPAR2;
use Bio::SeqFeature::Gene::Exon;
use Bio::SeqFeature::Generic;

# constants

sub setup  {
    my $self = shift;
    my $q = $self->query();
    $self->start_mode('t_home');
    $self->tmpl_path(ABS_TEMPLATE_DIR);
    $self->run_modes(
		     't_home'           => \&t_homePage,
		     't_input'          => \&t_inputForm,
		     't_input_single'   => \&t_inputForm_single,
		     't_input_readyaln'   => \&t_inputForm_readyaln,
		     't_select'         => \&t_select,
		     't_select_single'  => \&t_select_single,
		     't_select_readyaln'  => \&t_select_readyaln,
		     't_view'           => \&t_view,
		     't_view_single'    => \&t_view_single,
		     't_info'           => \&t_info
		     );
    $self->{dbh} =  
      TFBS::DB::JASPAR2->connect("dbi:mysql:".DBI_DBNAME.":".DBI_HOST, 
				 DBI_USER, 
				 DBI_PASS);
    if (my $jobID = $self->query->param('jobID'))  {
	$self->{job} = CONSITE::Job->load(ABS_TMP_DIR.$jobID);
	if (my @list = $self->{job}->IDlist())  {
	    $self->{job}->MatrixSet
		($self->{dbh}->get_MatrixSet(-matrixtype=>"PWM",
					     #-min_ic=>$self->{job}->min_ic(),
					     -IDs => [$self->{job}->IDlist]));
	}
    }
    $self->{params} = {'IMAGE_DIR' => REL_IMG_DIR,
		       'WEBSERVER'    =>  WEBSERVER };
    if ($self->{job})  {
	no strict 'refs';
	foreach (qw(rangeref cutoff threshold window))  {
	    if (defined $q->param($_))  {
		$self->{job}->$_($q->param($_));
		if ($_ eq 'threshold')  {
		    $self->{job}->$_($q->param($_)."%");
		}
	    }
	    $self->{params}->{uc $_} = $self->{job}->$_();
	    $self->{params}->{uc $_} =~ s/\%//;  		
	}
    }		
}


sub teardown  {
    my $self = shift;
    if (defined $self->{job})  { 
	$self->{job}->MatrixSet(undef);
	$self->{job}->commit();
    }

}


sub t_info  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("info.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    return $template->output();
}


sub t_homePage  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("frameset.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    return $template->output();
}


sub t_inputForm  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("input.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    $template->param
	('HIDDEN' => $q->hidden(-name=>"rm", 
				-value=>"t_select", 
				-override=>1),
	 'ALIGNMENT' =>1,
	 'MAX_SEQ_LENGTH' => MAX_SEQ_LENGTH);
    return $template->output();
}


sub t_inputForm_single  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("input.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    $template->param
	('HIDDEN' => $q->hidden(-name=>"rm", 
				-value=>"t_select_single", 
				-override=>1),
	 'SINGLE' =>1);
    return $template->output();
}


sub t_inputForm_readyaln  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("input.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    $template->param
	('HIDDEN' => $q->hidden(-name=>"rm", 
				-value=>"t_select_readyaln", 
				-override=>1),
	 'READYALN' =>1);
    return $template->output();
}


sub t_view_single  {
    my ($self) = @_;
    my $q = $self->query;

    # see whether we were called from the selection form

    if (defined $q->param('select_by'))  {
	$self->create_ID_list_or_user_matrix();
    }
    
    my $template = $self->load_tmpl("view.html",
				    die_on_bad_params =>0 );
    $q->param('rangeref', 1) unless defined $q->param('rangeref');
    $template->param( %{$self->{params}} );
    my $singleseqobject = $self->create_singleseqobject();
    #my $alignobject = (#$self->{job}->alignobject() or
	#	       $self->create_alignobject());
    $template->param
	('HIDDEN' => $q->hidden(-name=>"rm", 
				-value=>"t_view_single", 
				-override=>1).
	             $q->hidden(-name=>"jobID", 
				-value=>$self->{job}->jobID(), 
				-override=>1),
	 'RANGEREF'.$q->param('rangeref') => 1,
	 'START_AT' => 
	   ($singleseqobject->pdlindex($singleseqobject->start_at(), 
				   0 => $q->param('rangeref'))
	    or $q->param('start_at')
	    or 1),
	 'END_AT' => 
	   ($singleseqobject->pdlindex($singleseqobject->end_at(), 
				   0 => $q->param('rangeref'))
	    or $q->param('end_at')
	    or $self->{job}->seq1->length()),
				   
	 'SEQ1NAME' => $self->{job}->seq1->id()."",
	 #'SEQ2NAME' => $self->{job}->seq2->id()."",
	 'SEQ3NAME' => "",
	 'SINGLE' =>1 ); # $self->{job}->seq3->id()."");


    
    print STDERR ">>>STARTAT ENDAT rangeref". $template->param('START_AT') ." ".
	$template->param('END_AT')." ".$q->param('rangeref') ."\n";
    my $output;

    if ($q->param('mode') eq 'Table') {
	$template->param(TITLE_IMG=>'table_title.PNG',
			 MODE => 'Table',
			 TABLE => 1);
	$output = $singleseqobject->HTML_table;
    }
    elsif ($q->param('mode') eq 'Alignment')  {
	$template->param(TITLE_IMG=>'alignment_title.PNG',
			 MODE => 'Alignment',
			 ALIGNMENT => 1);
	$output = $q->table({-align=>"left"},
			    $q->Tr($q->td({-align=>"left"}, 
					  $q->pre($q->font({-size=>-1},
			   $singleseqobject->HTML_seqview)))));
    }
    else  {
	$template->param(TITLE_IMG=>'graphical_title.PNG',
			 MODE => 'Graphical',
			 GRAPHICAL =>1);
	$output = $singleseqobject->HTML_image;
    }	 
    $template->param('VIEW_RESULTS' => $output);
    $template->param('jobID' => $self->{job}->jobID());
    return $template->output();
}


sub t_view  {
    my ($self) = @_;
    my $q = $self->query;

    # check if the alignment is ready; if not, go to waiting page

    unless ($self->{job}->alignstring)  {
	my $hidden ="";
	foreach my $param ($q->param())  {
	    $hidden .= $q->hidden(-name=>$param, -value=>$q->param($param));
	}
	my $template = $self->load_tmpl("waiting.html",
					die_on_bad_params => 0);
	$template->param( %{$self->{params}} );
	$template->param(HIDDEN=>$hidden);
	
	return $template->output();
    }

    # see whether we were called from the selection form

    if (defined $q->param('select_by'))  {
	$self->create_ID_list_or_user_matrix();
    }
    
    my $template = $self->load_tmpl("view.html",
				    die_on_bad_params =>0 );
    $q->param('rangeref', 1) unless defined $q->param('rangeref');
    $template->param( %{$self->{params}} );
    my $alignobject = (#$self->{job}->alignobject() or
		       $self->create_alignobject());
    $template->param
	('HIDDEN' => $q->hidden(-name=>"rm", 
				-value=>"t_view", 
				-override=>1).
	             $q->hidden(-name=>"jobID", 
				-value=>$self->{job}->jobID(), 
				-override=>1),
	 'RANGEREF'.$q->param('rangeref') => 1,
	 'START_AT' => 
	   ($alignobject->pdlindex($alignobject->start_at(), 
				   0 => $q->param('rangeref'))
	    or $q->param('start_at')
	    or 1),
	 'END_AT' => 
	   ($alignobject->pdlindex($alignobject->end_at(), 
				   0 => $q->param('rangeref'))
	    or $q->param('end_at')
	    or ($self->{job}->seq1->length(),$self->{job}->seq2->length())
	       [$q->param('rangeref')-1]),
	 'CUTOFF'   =>  $self->{job}->cutoff(),
	 'SEQ1NAME' => $self->{job}->seq1->id()."",
	 'SEQ2NAME' => $self->{job}->seq2->id()."",
	 'SEQ3NAME' => "" ); # $self->{job}->seq3->id()."");


    
    print STDERR ">>>STARTAT ENDAT rangeref". $template->param('START_AT') ." ".
	$template->param('END_AT')." ".$q->param('rangeref') ."\n";
    my $output;

    if ($q->param('mode') eq 'Table') {
	$template->param(TITLE_IMG=>'table_title.PNG',
			 MODE => 'Table',
			 TABLE => 1);
	$output = $alignobject->HTML_table;
    }
    elsif ($q->param('mode') eq 'Alignment')  {
	$template->param(TITLE_IMG=>'alignment_title.PNG',
			 MODE => 'Alignment',
			 ALIGNMENT => 1);
	$output = $q->table({-align=>"left"},
			    $q->Tr($q->td
				   ($q->a({-href=>WEBSERVER."/cgi-bin/consite.savealn?jobID=".$self->{job}->jobID()}, "Save alignment in Clustal format"))),
			    $q->Tr($q->td({-align=>"left"}, 
					  $q->pre($q->font({-size=>-1},
			   $alignobject->HTML_alignment)))));
    }
    else  {
	$template->param(TITLE_IMG=>'graphical_title.PNG',
			 MODE => 'Graphical',
			 GRAPHICAL =>1);
	$output = $alignobject->HTML_image;
    }	 
    $template->param('VIEW_RESULTS' => $output);
    $template->param('jobID' => $self->{job}->jobID());
    return $template->output();
}

sub create_ID_list_or_user_matrix  {
    my $self = shift;
    my $q = $self->query();
    if ($q->param('matrixstring') and $q->param('matrixtype'))  {
	$self->_create_user_matrix();
    }
    else  {
	$self->_create_ID_list();
    }
}

sub _create_user_matrix  {
    my ($self) = @_;
    my $q = $self->query();
    my $user_matrix = 
      CONSITE::UserMatrix->new(-name => $q->param('matrixname')."",
			       -matrixstring => $q->param('matrixstring'),
			       -type   => $q->param('matrixtype'));
    $self->{job}->user_matrix($user_matrix);
	
}

sub _create_ID_list  {
    my ($self) = @_;
    $self->{job}->IDlist_clear();
    my $q = $self->query();
    my $min_ic = ( ($q->param('min_ic_set') and $q->param('min_ic')) or 0 ) ;
    $min_ic = 0 if $q->param('sel_type') eq 'names';
    print STDERR 'SEL_TYPE '.$q->param('sel_type'). "\n";
    if ($q->param('sel_type') eq 'all')  {
	my @IDlist = $self->{dbh}->_get_ID_list();
	if ($min_ic)  {
	    foreach (@IDlist)  {
		print STDERR "ICs : ".
		    join(" :: ", ($min_ic,
				  $self->{dbh}->_get_total_ic($_),
				  ($self->{dbh}->_get_total_ic($_) >= $min_ic)));

		$self->{job}->IDlist_push($_) 
		    if  ($self->{dbh}->_get_total_ic($_) >= $min_ic);
	    }
	}
	else  {
	    $self->{job}->IDlist_push(@IDlist);
	}
    print STDERR "IDLIST : ".(@{$self->{job}->IDlist})."\n";
    }

    else  {
	my $temp_MatrixSet = TFBS::MatrixSet->new();
	$self->{job}->MatrixSet( TFBS::MatrixSet->new() );
	my %exists;
	my %allowed_type = qw(names 1 IDs 1 classes 1 species 1 sysgroups 1);
	if ($allowed_type{my $type = $q->param('sel_type')}) {
	    my @list = $q->param($type);

	    if (@list)  {
		print STDERR ("XXX",$type," ", join(" ", @list), "\n" );
		$temp_MatrixSet = 
		    $self->{dbh}->get_MatrixSet("-$type" => [@list],
						 -matrixtype => 'PWM',
						 -min_ic => $min_ic);
	    

		$temp_MatrixSet->reset();
		while (my $Matrix = $temp_MatrixSet->next())  {
		    print STDERR "YYY $Matrix->{ID}\n";
		    $self->{job}->MatrixSet->add_Matrix($Matrix) 
			unless $exists{$Matrix->{ID}};
		    $exists{$Matrix->{ID}} = 1;
		}
	    }
	}

	$self->{job}->IDlist_push(sort keys %exists);
    }
		
}


sub t_select_single  {

    my $self = shift;
    my $q = $self->query;

    my $jobID = ($q->param('jobID') or time.sprintf("%04d", rand(10000)));
    $q->param(jobID    => $jobID);
    $q->param(analysis => 'SINGLE');

    $self->create_job_single($jobID);
    $self->matrixSelectionForm();
}

sub t_select_readyaln  {

    my $self = shift;
    my $q = $self->query;

    my $jobID = ($q->param('jobID') or time.sprintf("%04d", rand(10000)));
    $q->param(jobID    => $jobID);
    $q->param(analysis => 'ALIGNMENT');

    $self->create_job_readyaln($jobID);
    $self->matrixSelectionForm();
}


sub t_select  {
    my $self = shift;
    my $q = $self->query;

    my $jobID = ($q->param('jobID') or time.sprintf("%04d", rand(10000)));

    # here we assign the ID to the process and fork off the process
    unless (my $f = fork)  {
	exit if (defined $q->param('jobID'));
	close (STDERR);
	close (STDOUT);
	$self->align_sequences_and_create_job($jobID);
    }
    else  {
	$q->param(jobID    => $jobID);
	$q->param(analysis => 'ALIGNMENT');
	$self->matrixSelectionForm();
    }
}

sub matrixSelectionForm  {

    my $self = shift;
    my $q = $self->query;
    
    my $tfp = CONSITE::TFpicker->new($self->{dbh});
    my $template = $self->load_tmpl("select.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );
    
    if ($q->param('select_by') eq "class")  {
	$template->param('SELECTION_TABLE' => $tfp->class_table());
    }
    elsif ($q->param('select_by') eq "name") {
	$template->param('SELECTION_TABLE' => $tfp->name_table());
    }
    elsif ($q->param('select_by') eq "species") {
	$template->param('SELECTION_TABLE' => $tfp->species_table());
    }
    elsif ($q->param('select_by') eq "usermatrix") {
	$template->param('SELECTION_TABLE' => $tfp->user_matrix_table());
    }
    else  {
	$template->param('SELECTION_TABLE' => $tfp->name_table());
    }
    $template->param
	('HIDDEN' => 
	 $q->hidden(-name=>"rm", 
		    -value=>($q->param('analysis') eq "SINGLE" ?
			     "t_view_single" : "t_view"), 
		    -override=>1).
	 $q->hidden(-name=>"select_by", 
		    -value=>($q->param('select_by') or "name"), 
		    -override=>1).
	 $q->hidden(-name=>'jobID', -value=>$q->param('jobID'), 
		    -override=>1));
    $template->param('jobID' => $q->param('jobID'));
    if ($q->param('analysis') eq "SINGLE")  { $template->param('SINGLE' =>1); }
    return $template->output();
}





#########################################################################
# ANALYSIS ROUTINES: not visual

sub create_job_single  {

    my ($self, $jobID) = @_;
    my $q = $self->query();
    my $output = "";

    foreach ($q->param())  {
  	$output .= $q->p([$_, $q->param($_)])
  	    if /seq/ and $DEBUG;
    }
    my ($seq1, $seq3) = 
	(getSequence($q->param('seq1'), 
		     $q->param('seq1acc'), 
		     $q->param('seq1fh')
		     ),
	 getSequence($q->param('seq3'), 
		     $q->param('seq3acc'),
		     $q->param('seq3fh')
		     )
	 );
    my ($header1, $header3) = 
	($q->param('seq1name'), 
	 $q->param('seq3name') );
    $header1 =~ s/ /_/g; $header3 =~ s/ /_/g;
    $output .= $q->p([$seq1,  $header1])
	if $DEBUG;

    my $strand1 = 1; # plus by default
    my $strand3;     # is returned by _find_exons below 

    # create sequence objects
    my $seqobj1 = Bio::Seq->new(-seq => $seq1, -id => $header1);
    my $seqobj3 = 
	defined($seq3) 
	    ? Bio::Seq->new(-seq => $seq3, -id => $header3) : undef;
    
    # find exons if $seq3 is defined
    if ($seq3)  {
	$strand3 = $self->_find_exons ($seqobj1, $seqobj3);
    }
       
    # invert strands if cDNA is chosen as the reference

    if ($q->param('strandref') 
	and $q->param('strandref')==3
	and $strand3)  
    {
	$strand1 *= $strand3; $strand3 *= $strand3;
    }
	
    print STDERR "/nTOCKA 4/n";
    # find orf if appropriate

    if ($seqobj3 and $q->param('find_orf'))  { #($q->param('find_orf') == 1)  {
	$self->_find_orf($seqobj3); 
    }
    
    print STDERR "/nTOCKA 5/n";
    # create job object

    my $job = CONSITE::Job->new(-jobID=>$jobID,
				-seq1 =>$seqobj1,
				-seq3 =>$seqobj3);

    # add strands to job

    $job->strand1($strand1);
    $job->strand3($strand3);
    $job->strandref($q->param('strandref') or 1);
    $job->exclude_orf($q->param('exclude_orf')
		       or 0);

    # store job on disk


    Persistence::Object::Simple->commit( __Fn=>$job->tmpdir()."/".$jobID, 
					 Data=>$job);
	

} 


sub create_job_readyaln  {

    my ($self, $jobID) = @_;
    my $q = $self->query();
    my $output = "";
    my $seq3 = getSequence($q->param('seq3'), 
			   $q->param('seq3acc'),
			   $q->param('seq3fh')
			   );
    my $FH = ($q->param('alignFH') or $self->throw("No alignment filehandle provided"));
    my $alignstring;

    {
	# slurp in the entire alignment:
	local $/ = undef;
	$alignstring = <$FH>;
    }

    my ($seqobj1, $seqobj2) = 
	$self->_seqobjs_from_clustal($alignstring);
    my $strand1 = 1; # plus by default
    my $strand2 = 1; # plus by default
    my $strand3;     # is returned by _find_exons below 

    my $header3 = 
	 $q->param('seq3name');
     my $seqobj3 = 
	defined($seq3) 
	    ? Bio::Seq->new(-seq => $seq3, -id => $header3) : undef;
    

    # INCREDIBLY ugly; no time for anything prettier:

    # find exons if $seq3 is defined

    if ($seq3)  {
	$strand3 = $self->_find_exons ($seqobj1, $seqobj3);
    }
       

    # invert strands if cDNA is chosen as the reference

    if ($q->param('strandref') 
	and $q->param('strandref')==3
	and $strand3)  
    {
	$strand1 *= $strand3; $strand2 *= $strand3; $strand3 *= $strand3;
    }
	
    # find orf if appropriate

    if ($seqobj3 and $q->param('find_orf'))  { #($q->param('find_orf') == 1)  {
	$self->_find_orf($seqobj3); 
    }
    
    
    # create job object

    my $job = CONSITE::Job->new(-jobID=>$jobID,
				-seq1 =>$seqobj1,
				-seq2 =>$seqobj2,
				-seq3 =>$seqobj3,
				-alignstring => $alignstring);

    # add strands to job

    $job->strand1($strand1); $job->strand2($strand2); $job->strand3($strand3);
    $job->strandref($q->param('strandref') or 1);
    $job->exclude_orf($q->param('exclude_orf')
		       or 0);

    # store job on disk

    Persistence::Object::Simple->commit( __Fn=>$job->tmpdir()."/".$jobID, 
					 Data=>$job);

}


sub _seqobjs_from_clustal  {
    my ($self, $alignstring) = @_;

    # returns seq1sreing, seq2string, label1, label2
    my ($seq1string, $seq2string, $seq1name, $seq2name);
    
    my @alnlines = split("\n", $alignstring);
    shift @alnlines;shift @alnlines;shift @alnlines; # drop header
    
    while ($_=shift @alnlines) {
	my ($label1, $string1) = split; 
	$seq1name = $label1 unless $seq1name;
  	my ($label2, $string2) = split /\s+/, shift(@alnlines); 
 	$seq2name = $label2 unless $seq2name;
	shift @alnlines; shift @alnlines; # skip asterisk line and blank line
	$seq1string .= $string1;
	$seq2string .= $string2;
    }

    unless ($seq1string 
	    and $seq2string 
	    and length($seq1string)==length($seq2string))  {
	$self->throw("There was an error parsing the alignment");
    }

    # create sequence objects
    my $seqobj1 = Bio::Seq->new(-seq => _strip_gaps($seq1string), 
				-id  => $seq1name);
    my $seqobj2 = Bio::Seq->new(-seq => _strip_gaps($seq2string), 
				-id  => $seq2name);

    return ($seqobj1, $seqobj2);
}


sub _strip_gaps {
    # not OO
    my $seq = shift;
    $seq =~ s/\-|\.//g;
    return $seq;
}



sub align_sequences_and_create_job  {

    my ($self, $jobID) = @_;
    my $q = $self->query();
    my $output = "";

    foreach ($q->param())  {
  	$output .= $q->p([$_, $q->param($_)])
  	    if /seq/ and $DEBUG;
    }

    # prepare and run DPB
    
    my ($seq1, $seq2, $seq3) = 
	(getSequence($q->param('seq1'), 
		     $q->param('seq1acc'), 
		     $q->param('seq1fh')
		     ),
	 getSequence($q->param('seq2'), 
		     $q->param('seq2acc'),
		     $q->param('seq2fh')
		     ),
	 getSequence($q->param('seq3'), 
		     $q->param('seq3acc'),
		     $q->param('seq3fh')
		     )
	 );
    my ($header1, $header2, $header3) = 
	($q->param('seq1name'), 
	 $q->param('seq2name'), 
	 $q->param('seq3name') );
    $header1 =~ s/ /_/g; $header2 =~ s/ /_/g; $header3 =~ s/ /_/g;

    $output .= $q->p([$seq1, $seq2, $header1, $header2])
	if $DEBUG;
    
    my $strand1 = 1; # plus by default
    my $strand3;     # is returned by _find_exons below 
    my ($alignstring, $strand2) = 
	DPB_remote($seq1, $seq2, $header1, $header2);
    


    # create sequence objects
    my $seqobj1 = Bio::Seq->new(-seq => $seq1, -id => $header1);
    my $seqobj2 = Bio::Seq->new(-seq => $seq2, -id => $header2);
    my $seqobj3 = 
	defined($seq3) 
	    ? Bio::Seq->new(-seq => $seq3, -id => $header3) : undef;
    
    # find exons if $seq3 is defined
    if ($seq3)  {
	$strand3 = $self->_find_exons ($seqobj1, $seqobj3);
	#$self->_find_exons ($seqobj2, $seqobj3);
    }
       

    # invert strands if cDNA is chosen as the reference

    if ($q->param('strandref') 
	and $q->param('strandref')==3
	and $strand3)  
    {
	$strand1 *= $strand3; $strand2 *= $strand3; $strand3 *= $strand3;
    }
	
    # find orf if appropriate

    if ($seqobj3 and $q->param('find_orf'))  { #($q->param('find_orf') == 1)  {
	$self->_find_orf($seqobj3); 
    }
    
    
    # create job object

    my $job = CONSITE::Job->new(-jobID=>$jobID,
				-seq1 =>$seqobj1,
				-seq2 =>$seqobj2,
				-seq3 =>$seqobj3,
				-alignstring => $alignstring);

    # add strands to job

    $job->strand1($strand1); $job->strand2($strand2); $job->strand3($strand3);
    $job->strandref($q->param('strandref') or 1);
    $job->exclude_orf($q->param('exclude_orf')
		       or 0);

    # store job on disk


    Persistence::Object::Simple->commit( __Fn=>$job->tmpdir()."/".$jobID, 
					 Data=>$job);
	

}

sub _find_orf  {
    my ($self, $cdnaobj) = @_;
    my ($cdnaFH, $cdnafile) = tempfile(DIR=>ABS_TMP_DIR);
    print STDERR "cDNA FILE $cdnafile\n";
    my $outfile = ABS_TMP_DIR."/papak.out";
    Bio::SeqIO->new(-fh=>$cdnaFH, -format=>"Fasta")->write_seq($cdnaobj);
    close $cdnaFH; 
    my @args = split /\s+/,  
              "/usr/local/bin/getorf -sequence $cdnafile -outseq $outfile";
    system(@args)==0 or (print STDERR "System call failed:$?"); #wait;
    my @outlines = split("\n", `grep '>' $outfile`);
    print STDERR ("\nOUTFILE:",`grep '>' $outfile`);
    my $longest = 0; my ($orf_start, $orf_end);
    my $strand;
    foreach my $line (@outlines)  {
	if ($line =~ /\[(\d+) \- (\d+)\]/)  {
	    if ((my $orf_length = abs($2-$1) +1) > $longest)  {
		$strand = ($2 > $1)*2 -1; # can be -1 or 1
		($orf_start, $orf_end) = sort {$a<=>$b} ($1, $2);
		$longest = $orf_length;
	    }
	}
    }
    my $orf = Bio::SeqFeature::Generic->new (-start=>$orf_start,
					     -end  =>$orf_end,
					     -primary => 'orf',
					     -strand => $strand);

    # add orf to sequence object

    $cdnaobj->add_SeqFeature($orf);
}

sub _find_exons  {

    my ($self, $geneobj, $cdnaobj) = @_;
    my ($geneFH, $genefile) = tempfile(DIR=>ABS_TMP_DIR);
    my ($cdnaFH, $cdnafile) = tempfile(DIR=>ABS_TMP_DIR);
    my $outfile = "$cdnafile.out";

    Bio::SeqIO->new(-fh=>$geneFH, -format=>"Fasta")->write_seq($geneobj);
    Bio::SeqIO->new(-fh=>$cdnaFH, -format=>"Fasta")->write_seq($cdnaobj);
    close $geneFH; close $cdnaFH; sleep 1;

    my @args = split /\s+/,  
              "/usr/local/bin/est2genome -est $cdnafile -genome $genefile -outfile $outfile -space 100000";
    system(@args)==0 or (print STDERR "System call failed:$?"); 

    my $outstring = `cat $outfile` ;
    print STDERR $outstring;
    my @outlines = 
	split("\n", $outstring);
    unlink $genefile; unlink $cdnafile; unlink $outfile;

    my $exon_no = 0;
    my $strand = 1;
    foreach my $line (@outlines)  {

	if ($line =~ /reversed est and forward genome/)  {
	    $strand = -1;
	}
	next unless $line =~ /^Exon\s/;
	$exon_no++;
	my @col=split(/\s+/, $line);
	my ($geneexon_start, $geneexon_end) = ($col[3], $col[4]);
	my ($cdnaexon_start, $cdnaexon_end) = ($col[6], $col[7]);

	if ($strand==-1)  {
	    ($cdnaexon_start, $cdnaexon_end) =
		($cdnaobj->length() - $col[7] + 1,
		 $cdnaobj->length() - $col[6] + 1);
	}
	
	my $geneexon = 
	  Bio::SeqFeature::Gene::Exon->new(-start => $col[3],
				      -end   => $col[4],
				      -tag   => { number => $exon_no});
	$geneobj->add_SeqFeature($geneexon);
	my $cdnaexon = 
	  Bio::SeqFeature::Gene::Exon->new(-start => $col[6],
				      -end   => $col[7],
				      -tag   => { number => $exon_no});
	$cdnaobj->add_SeqFeature($cdnaexon);

    }

    return $strand;
}
    
    
    
sub create_singleseqobject  {
    my $self = shift;
    my $q = $self->query();
    
#    my $set = $self->{dbh}->get_MatrixSet
#        (-IDs=> [$self->{job}->IDlist()], 
#         -matrixtype=>"PWM"
#         ) ;

    my $set = $self->get_MatrixSet();

    my %singleseq_params = 	
	(-job         => $self->{job}, # this is temporary
	 -window      => $self->{job}->window(),
	 -cutoff      => $self->{job}->cutoff(),
	 -MatrixSet   => $set);
    if (!defined($q->param('select_by')) 
	and defined $q->param('start_at') 
	and defined $q->param('end_at'))
    {
	%singleseq_params = 	
	    ( %singleseq_params,
	      -start    => $q->param('start_at'),
	      -end      => $q->param('end_at'));
    }
    my $sso = CONSITE::SingleSeq->new(%singleseq_params);
    return $sso;

}


sub create_alignobject  {
    my $self = shift;
    my $q = $self->query();
    
#      my $set = $self->{dbh}->get_MatrixSet
#          (-IDs=> [$self->{job}->IDlist()], 
#           -matrixtype=>"PWM"
#           );

    my $set = $self->get_MatrixSet();
    print STDERR "In create_alignobject:\n $set\n";

    my %alignment_params = 	
	(-job         => $self->{job}, # this is temporary
	 -alignstring => $self->{job}->alignstring,
	 -window      => $self->{job}->window(),
	 -cutoff      => $self->{job}->cutoff()."",
	 -seqobj1     => $self->{job}->seq1(),
	 -MatrixSet   => $set);
    if (!defined($q->param('select_by')) 
	and defined $q->param('start_at') 
	and defined $q->param('end_at'))
    {
	%alignment_params = 	
	    ( %alignment_params,
	      -start    => $q->param('start_at'),
	      -end      => $q->param('end_at'));
    }
    my $aln = CONSITE::Alignment->new(%alignment_params);
    return $aln;
    #$self->{job}->alignobject($aln);

}

sub get_MatrixSet  {
    my $self = shift;

    # this sub has to take into account the possibility that
    # a matrix set can either come from a database, retrieved by
    # $self->{job}->IDlist(), OR from a single, user-defined matrix

    my $set;
    if (defined $self->{job}->user_matrix())  {
	$set = $self->{job}->user_matrix->get_MatrixSet(-matrixtype=>"PWM");
    }
    else  {
	$set = $self->{dbh}->get_MatrixSet
        (-IDs=> [$self->{job}->IDlist()], 
         -matrixtype=>"PWM"
         );
	print STDERR "in get_Matrixset (no user matrix)\n: ".keys(%$set)."\n"
    }
    return $set;
}

sub user_matrix {
    my ($self, %args) = @_;
    if ($args{'-matrixstring'})  {
	my $name = ($args{'name'} or 'Unknown');
	my $id = "User_defined";
	# unfinished
    }
    else  {
	
    }
}

sub saveList  {
    my $self = shift;
    my $q = $self->query();
    
    my $output = header('application/octet-stream');
    my @factorList =  qw(AA BC THG TFM CREB S12); # Jaspar->get_factor_list
    foreach (@factorList)  {
	if (1)  {  #($self->param($_) eq "1")  {
	    $output .= "$_\n";
	}
    }
    print $output;
    exit;
}



############################################################################
#  SEQUENCE PARSING


sub getSequence  {
    my ($seq, $acc, $fh) = @_;
    
    my $seqstring = "";

    if ($seq)  {
	$seqstring=ParseSequence ($seq) or ExitError ("Error parsing sequence.");
    }
    elsif ($acc)  {
	use Bio::Seq;
	use Bio::DB::GenBank;
	my $gb=new Bio::DB::GenBank;
	my $seqobj= new Bio::Seq;
	eval {$seqobj=$gb->get_Seq_by_acc($acc) };
	if ($@)  { 
	    ExitError("Could not retrieve nucleotide sequence ".
		      "with the accession number ".
		      "<B>".param("accession")."</B> ".
		      "Check the accession number or try again later.");
	}
	$seqstring=$seqobj->seq();
    }
    elsif ($fh)
    {
	my $rawseq;
	my $FILEHANDLE=$fh or die;
	while (<$FILEHANDLE>)
	{
	    $rawseq .=$_;
	}
	# print $rawseq;
	$seqstring=ParseSequence ($rawseq) 
	    or ExitError ("Error parsing uploaded sequence.");
    }
    else {
	return undef;
    }
    # truncate if too big

    if  (length($seq) > MAX_SEQ_LENGTH) {
	$seqstring = substr($seqstring, 0, MAX_SEQ_LENGTH);
    }
    return $seqstring;
}



sub ParseSequence  {
    my $rawseq = shift;
    #print "<p>RAWSEQ: $rawseq</p>";
    my @lines=split("\n", $rawseq);
    my $seq = "";
    foreach (@lines)  {
	s/^\s+//;
	$_=uc($_);
	if (/^>/)  {
	    last if $seq;
	}
	else  {
	    s/[\s+|\d+]//g;
	    ValidateSeq($_, 'N') 
		or ExitError 
		    ("Illegal character(s) in nucleotide query sequence, ".
		     "line:<BR>$_");
	    $seq .=$_;
	}	
    }
	
    if ($seq) { return $seq}
    else      { ExitError ("No sequence provided.") }
    
}


sub ValidateSeq  {
    my ($sequence, $seqtype)=@_;
    if ($seqtype eq "N")  {
	$sequence=~ s/[ACGTWSKMPUYBDHWN]//g;
    }
    elsif ($seqtype eq "P")  {
	$sequence=~ s/[ABCDEFGHIKLMNPQRSTVWXYZ]//g;
    }
    else  {
	return 0;
    }
    
    ($sequence eq "") ? return 1 : return 0;
}

##########################################################################
# Exception throwing

sub ExitError  {
    my $errormsg = shift;
    print header("text/plain"),
    print $errormsg;
    exit;
}

########################################################################
# RUN DPB REMOTELY

sub DPB_remote  {
    my ($seq1, $seq2, $header1, $header2) = @_;
    my $ua = LWP::UserAgent->new(timeout => DPB_TIMEOUT);
    my $response =  $ua->request(POST DPB_CGI, 
		  [seq1 => $seq1."", 
		    seq2 => $seq2."",
		    header1 => $header1."", 
		    header2 => $header2
		    ] );
    
    my @alignment_lines = 
	split "\n", $response->{'_content'};
    
    my $strand = pop (@alignment_lines);
    if ($strand eq "FAILED")  {

	# DPB crash handling instruction goes here

    }
    unless ($strand==1 or $strand==-1) {
	push @alignment_lines, $strand;
	$strand=1;
    }
    return join("\n", @alignment_lines)."\n", $strand;
}
  
   
1;

