package CONSITE_Interface;


#################################################################
# CHANGES
#
# 2001-05-25 Added relative (90-th parcentile) cutoff to analyses
#
#################################################################

use base 'CGI::Application';
use CONSITE_OPT;
use lib CONSITE_PERLLIB;
use lib CONSNP_PERLLIB;
use lib GL_PERLLIB;
use lib AT_PERLLIB;
use lib ORCA_LIB;

my $DEBUG = DEBUGGING_ON;
use vars qw'%LAYOUT_PARAMS *LOG';


use CGI qw(Tr table td header);
use CGI::Carp qw(carpout);# fatalsToBrowser);
    open (LOG, ">>".LOG_DIR."/CONSITE.errorlog.".($ENV{"USER"} or "nobody"))
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
use Orca;
use Bio::SeqFeature::Gene::Exon;
use Bio::SeqFeature::Generic;
use Bio::SeqIO;
use Bio::Seq;
use Bio::DB::GenBank;
use AT::DB::GenomeMapping;
use AT::DB::GenomeAssembly;

use CONSNP::Run::Align;
use ConSNPWeb::Environment;
use GeneLynx::MySQLdb;
use GeneLynx::Search::MultiSpecies::Quick;
use ConSNPWeb::Page::GeneLynxSearchResult;
use ConSNPWeb::Page::SelectRelativeGenomicSeq;

# GRAFTED FROM CONSNP's interface

my %spdb = ();
    #(   human => GeneLynx::MySQLdb->connect(-dbname => HUMAN_GENELYNX_DB_NAME,
    #                                        -dbuser => HUMAN_GENELYNX_DB_USER,
    #                                        -dbpass => HUMAN_GENELYNX_DB_PASS,
    #                                        -dbhost => HUMAN_GENELYNX_DB_HOST),
    #    mouse => GeneLynx::MySQLdb->connect(-dbname => MOUSE_GENELYNX_DB_NAME,
    #                                        -dbuser => MOUSE_GENELYNX_DB_USER,
    #                                        -dbpass => MOUSE_GENELYNX_DB_PASS,
    #                                        -dbhost => MOUSE_GENELYNX_DB_HOST)
    #);
my %mapdb =
    (   human => AT::DB::GenomeMapping->connect(-dbname => HUMAN_MAPPING_DB_NAME,
                                                -dbuser => HUMAN_MAPPING_DB_USER,
                                                -dbpass => HUMAN_MAPPING_DB_PASS,
                                                -dbhost => HUMAN_MAPPING_DB_HOST),
        mouse => AT::DB::GenomeMapping->connect(-dbname => MOUSE_MAPPING_DB_NAME,
                                                -dbuser => MOUSE_MAPPING_DB_USER,
                                                -dbpass => MOUSE_MAPPING_DB_PASS,
                                                -dbhost => MOUSE_MAPPING_DB_HOST)
    );

my %genomedb =
    (   human =>AT::DB::GenomeAssembly->connect(-dbname => HUMAN_ASSEMBLY_DB_NAME,
                                                -dbuser => HUMAN_ASSEMBLY_DB_USER,
                                                -dbpass => HUMAN_ASSEMBLY_DB_PASS,
                                                -dbhost => HUMAN_ASSEMBLY_DB_HOST),
        mouse =>AT::DB::GenomeAssembly->connect(-dbname => MOUSE_ASSEMBLY_DB_NAME,
                                                -dbuser => MOUSE_ASSEMBLY_DB_USER,
                                                -dbpass => MOUSE_ASSEMBLY_DB_PASS,
                                                -dbhost => MOUSE_ASSEMBLY_DB_HOST)
    );


my $jaspardb = TFBS::DB::JASPAR2->connect("dbi:mysql:".JASPAR_DB_NAME.":".JASPAR_DB_HOST,
                                            JASPAR_DB_USER,
                                            JASPAR_DB_PASS);



# constants



sub setup  {
    my $self = shift;
    my $q = $self->query();
    $self->start_mode('t_home');
    $self->tmpl_path(ABS_TEMPLATE_DIR);
    $self->{dbh} = $jaspardb;
          #  TFBS::DB::JASPAR2->connect("dbi:mysql:".DBI_DBNAME.":".DBI_HOST,
	  #			 DBI_USER,
	  #			 DBI_PASS);

    # setup environment singleton

    $self->{env} = ConSNPWeb::Environment->new(genelynx_db => \%spdb,
                                      mapping_db  => \%mapdb,
                                      genome_db   => \%genomedb,
                                      #dbsnp       => \%dbsnp,
                                      pattern_db  => $jaspardb,
                                      query       => $q,
                                      parameters  => \%LAYOUT_PARAMS);




    $self->run_modes(
		     't_home'             => \&t_homePage,
		     't_input'            => \&t_inputForm,
		     't_input_single'     => \&t_inputForm_single,
		     't_input_readyaln'   => \&t_inputForm_readyaln,
		     't_select'           => \&t_select,
		     't_select_single'    => \&t_select_single,
		     't_select_readyaln'  => \&t_select_readyaln,
		     't_searchform'       => \&t_searchform,
		     't_genesearch'       => \&t_genesearch,
		     'selectrelseq'     => \&t_select_relative_genomic_seq,
		     'view'             => \&t_select_ttf_after_ortholog_fetch,  # a CONSNP hack
		     't_view'             => \&t_view,
		     't_view_single'      => \&t_view_single,
		     't_info'             => \&t_info,
                     'ExitError'          => \&ExitError
		     );
    my %event_handler = (
                 genomic_seqs_selected    => \&e_genomic_seqs_selected,

		);

   if (my $jobID = $self->query->param('jobID'))  {
       $self->{job} = CONSITE::Job->load(ABS_TMP_DIR."/$jobID");
       if (my @list = $self->{job}->IDlist()	   )  {
           $self->{job}->MatrixSet
           ($self->dbh->get_MatrixSet(-matrixtype=>"PWM",
				      -IDs => [$self->{job}->IDlist]));

	   print STDERR "DIE2 3\n";
       }
   }

    if ($q->param("event") and exists($event_handler{$q->param("event")}))  {
        $event_handler{$q->param("event")}->($self);
    }

    $self->{params} = {'IMAGE_DIR'       =>  REL_IMG_DIR,
		       'WEBSERVER'       =>  WEBSERVER,
		       'REL_CGI_BIN_DIR' =>  REL_CGI_BIN_DIR,
		       'REL_IMG_DIR' =>  REL_IMG_DIR,
		       'REL_HTML_DIR'    =>  REL_HTML_DIR
		       };
    print STDERR "DIE2 4\n";
    if ($self->{job})  {
	no strict 'refs';
	print STDERR "DIE2 5\n";

	foreach (qw(rangeref cutoff threshold window))  {
	    if (defined $q->param($_))  {
            $self->{job}->$_($q->param($_));
            if ($_ eq 'threshold')  {
                $self->{job}->$_($q->param($_)."%");
            }
	    }
	    $self->{params}->{uc $_} = $self->{job}->$_();
	    $self->{params}->{uc $_} =~ s/\%// if $self->{params}->{uc $_};
	}

    }
}


sub teardown  {
    my $self = shift;
    if (defined $self->{job})  {
        $self->{job}->MatrixSet(undef);
        $self->{job}->commit();
    }
    _clean_tempfiles();

}



# EVENT HANDLERS:

sub e_genomic_seqs_selected  {
    my $self = shift;
    my $q = $self->query;

    my $jobID = ($q->param('jobID') or time.sprintf("%04d", rand(10000)));
    my $env = ConSNPWeb::Environment->environment;  #fixme
    my ($SP1, $ACC1, $SP2, $ACC2, $SEQSTART, $SEQEND, $RELATIVE_TO) =
                                    ($q->param("sp1"),
                                     $q->param("acc1"),
                                     $q->param("sp2"),
                                     $q->param("acc2"),
                                     $q->param("seqstart"),
                                     $q->param("seqend"),
                                     $q->param("relative_to"));

    if ($SEQSTART > $SEQEND)  {
        ($SEQSTART, $SEQEND) = ($SEQEND, $SEQSTART);

    }

    my $map1 = ($mapdb{$SP1}->get_mappings_for_acc($ACC1))[0];
    my $transcriptobj1 = $map1->transcript_feature_object;
    my (%coord1) = _map_to_coord($map1, $SEQSTART, $SEQEND, $RELATIVE_TO);

    my $tss; # transcription start site
    if ($map1->strand eq "+")  {
        $tss = $map1->tStart;
    }
    elsif ($map1->strand eq "-") {
        $tss = $map1->tEnd;
    }
    else {
        croak "Illegal strand value";
    }

    my $map2 = ($mapdb{$SP2}->get_mappings_for_acc($ACC2))[0];
    my $transcriptobj2 = $map2->transcript_feature_object;
    my (%coord2) = _map_to_coord($map2, $SEQSTART, $SEQEND, $RELATIVE_TO);
    my $seqobj1 = $genomedb{$SP1}->get_genome_seq(%coord1)  ;
    my $seqobj2 = $genomedb{$SP2}->get_genome_seq(%coord2)  ;
    my $seqobj3 = $mapdb{$SP1}->get_query_seq($ACC1);

    if (!defined($seqobj3)) {
	    eval {
		my $seq = Bio::DB::GenBank
		              ->new()
			         ->get_Seq_by_acc($ACC1);
		$seqobj3 = Bio::Seq->new(-id => $ACC1, -seq=>$seq->seq);
	    };
    }

    print STDERR "FETCH ERROR: $@" if $@;


    my $ordseq1 = Bio::LocatableSeq->new(-id  => $SP1,
				-seq => $seqobj1->seq,
				-start=>1, -end=>$seqobj1->length);
    if ($map1->strand eq "-") {
        $ordseq1 = $ordseq1->revcom;
    }
    my $ordseq2 = Bio::LocatableSeq->new(-id  => $SP2,
				-seq => $seqobj2->seq,
				-start=>1, -end=>$seqobj2->length);



    my $alignment = CONSNP::Run::Align->new(seqobj1 => $ordseq1,
                                            seqobj2 => $ordseq2,
                                            method =>($q->param("alnmethod") or DEFAULT_ALIGNMENT_METHOD)
                                           );
    my $alignstring;
    my $stringfh = IO::String->new($alignstring);
    my $outstream = Bio::AlignIO->new(-format=>"clustalw",
				      -fh => $stringfh);
    $outstream->write_aln($alignment);
    $outstream->close;


    my $plainseq1 = Bio::Seq->new(-seq=>$ordseq1->seq,
			      -id => $SP1);


    $self->_find_exons ($plainseq1, $seqobj3);
    $self->{job} = CONSITE::Job->new(-jobID => $jobID,
				    -seq1 => $plainseq1,
				    -seq2 =>Bio::Seq->new(-seq=>$ordseq2->seq,
							  -id => $SP2),
				    -seq3 =>$seqobj3,
				    -alignstring => $alignstring

				    );
    print STDERR "ALIGNSTRING: $alignstring";
    $self->{job}->strandref($q->param('strandref') or 1);
    $self->_find_orf($seqobj3);
    $self->{job}->exclude_orf($q->param('exclude_orf')
		       or 1);

    # store job on disk


    Persistence::Object::Simple->commit( __Fn=>ABS_TMP_DIR."/".$jobID,
					 Data=>$self->{job});


}



# PAGES:

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
	 'SEQ3NAME' => "",
	 'SINGLE' =>1 );


    print STDERR ">>>STARTAT ENDAT rangeref". $template->param('START_AT') ." ".
	$template->param('END_AT')." ".$q->param('rangeref') ."\n";
    my ($output, $graphaln);

    if ($q->param('mode') eq 'Table') {
        $template->param(TITLE_IMG=>'table_title.PNG',
                 MODE => 'Table',
                 TABLE => 1);
        ($output, $graphaln) = $singleseqobject->HTML_table;
    }
    elsif ($q->param('mode') eq 'Alignment')  {
        my $seqview;
        ($seqview, $graphaln) = $singleseqobject->HTML_seqview;
        $template->param(TITLE_IMG=>'seq_view_title.PNG',
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
        ($output, $graphaln)  = $singleseqobject->HTML_image;
    }
    $template->param('GRAPHALN' => $graphaln);
    $template->param('VIEW_RESULTS' => $output);
    $template->param('jobID' => $self->{job}->jobID());

    print STDERR  $template->output();
    return $template->output();
}


sub t_view  {
    my ($self) = @_;
    my $q = $self->query;

    # see whether we were called from the selection form

    if (defined $q->param('select_by'))  {
        $self->create_ID_list_or_user_matrix();
    }

    # check if the alignment is ready; if not, go to waiting page

    unless ($self->{job}->alignstring)  {
	my $hidden ="";
	#foreach my $param ($q->param())  {
	#    $hidden .= $q->hidden(-name=>$param, -value=>$q->param($param));
	#}
	$hidden .= $q->hidden(-name => "jobID", -value=>$q->param("jobID"));
	$hidden .= $q->hidden(-name => "rm", -value=>$q->param("rm"));
	my $template = $self->load_tmpl("waiting.html",
					die_on_bad_params => 0);
	$template->param( %{$self->{params}} );
	my $seconds = ($q->param("seconds") ?  $q->param("seconds")*2 : 10);
	$template->param(HIDDEN=>$hidden,
	                 SECONDS => $seconds,
                     MILISECONDS => $seconds*1000,
                     JOB_ID => $q->param("jobID")
	);

	return $template->output();
    }
    print STDERR "DIE 2\n";


    my $template = $self->load_tmpl("view.html",
				    die_on_bad_params =>0 );
    $q->param('rangeref', 1) unless defined $q->param('rangeref');
    print STDERR "DIE 4\n";
    $template->param( %{$self->{params}} );
    my $alignobject = (#$self->{job}->alignobject() or
		       $self->create_alignobject());
    print STDERR "DIE 5\n";
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

    print STDERR "DIE 6\n";


    print STDERR ">>>STARTAT ENDAT rangeref". $template->param('START_AT') ." ".
	$template->param('END_AT')." ".$q->param('rangeref') ."\n";
    my ($output, $graphaln);

    if ($q->param('mode') eq 'Table') {
        $template->param(TITLE_IMG=>'table_title.PNG',
                 MODE => 'Table',
                 TABLE => 1);
        ($output,$graphaln) = $alignobject->HTML_table;
    }
    elsif ($q->param('mode') eq 'Alignment')  {
        my $alnview;
        ($alnview, $graphaln) = $alignobject->HTML_alignment;
        $template->param(TITLE_IMG=>'alignment_title.PNG',
                 MODE => 'Alignment',
                 ALIGNMENT => 1);
        $output = $q->table({-align=>"left"},
                    $q->Tr($q->td
                       ($q->a({-href=>REL_CGI_BIN_DIR."/consite.savealn?jobID=".$self->{job}->jobID()}, "Save alignment in Clustal format"))),
                    $q->Tr($q->td({-align=>"left"},
                          $q->pre($q->font({-size=>-1},
                   $alnview)))));
    }
    else  {
        $template->param(TITLE_IMG=>'graphical_title.PNG',
                 MODE => 'Graphical',
                 GRAPHICAL =>1);
        ($output, $graphaln) = $alignobject->HTML_image;
    }
    $template->param('GRAPHALN' => $graphaln);

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
    # print STDERR 'SEL_TYPE '.$q->param('sel_type'). "\n";
    if ($q->param('sel_type') eq 'all')  {
        my @IDlist = $self->dbh->_get_ID_list();
        if ($min_ic)  {
            foreach (@IDlist)  {
            print STDERR "ICs : ".
                join(" :: ", ($min_ic,
                      $self->dbh->_get_total_ic($_),
                      ($self->dbh->_get_total_ic($_) >= $min_ic)));

            $self->{job}->IDlist_push($_)
                if  ($self->dbh->_get_total_ic($_) >= $min_ic);
            }
        }

        else  {
            $self->{job}->IDlist_push(@IDlist);
        }
        print STDERR "IDLIST : ".(@{$self->{job}->IDlist})."\n";
    }

    elsif (($q->param("sel_type") eq "upload_list") and defined($q->param("tf_list_fh")))  {
        #local $/; undef $/;
        my $fh = $q->upload("tf_list_fh");
        my @list;
        while (my $idstring = <$fh>) {
            chomp $idstring;
            print STDERR "IN IDSTRING\n";
            $idstring =~ s/^\s+//; $idstring =~ s/\s+$//;
            push @list, $idstring;
        }
        #$self->{job}->IDlist_push(@idlist);
        my $temp_MatrixSet = TFBS::MatrixSet->new();
        $self->{job}->MatrixSet( TFBS::MatrixSet->new() );
        my %exists;
        if (@list)  {
            $temp_MatrixSet =
                $self->dbh->get_MatrixSet("-names" => [@list],
                                        -matrixtype => 'PWM',
                                        -min_ic => $min_ic);
            $temp_MatrixSet->reset();
            while (my $Matrix = $temp_MatrixSet->next())  {
                    # print STDERR "YYY $Matrix->{ID}\n";
                    $self->{job}->MatrixSet->add_Matrix($Matrix)
                    unless $exists{$Matrix->{ID}};
                    $exists{$Matrix->{ID}} = 1;

            }
        }

        $self->{job}->IDlist_push(sort keys %exists);

      }

    else  {
        my $temp_MatrixSet = TFBS::MatrixSet->new();
        $self->{job}->MatrixSet( TFBS::MatrixSet->new() );
        my %exists;
        my %allowed_type = qw(names 1 IDs 1 classes 1 species 1 sysgroups 1);
        if ($allowed_type{my $type = $q->param('sel_type')}) {
            my @list = $q->param($type);

            if (@list)  {
                $temp_MatrixSet =
                    $self->dbh->get_MatrixSet("-$type" => [@list],
                                 -matrixtype => 'PWM',
                                 -min_ic => $min_ic);


                $temp_MatrixSet->reset();
                while (my $Matrix = $temp_MatrixSet->next())  {
                    # print STDERR "YYY $Matrix->{ID}\n";
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

    my $errormsg = $self->create_job_readyaln($jobID);
    if ($errormsg) {
	return $self->ExitError($errormsg);
    }
    else {
	$self->matrixSelectionForm();
    }
}


sub t_select  {
    my $self = shift;
    my $q = $self->query;

    my $jobID = ($q->param('jobID') or time.sprintf("%04d", rand(10000)));

    # here we assign the ID to the process and fork off the process
    #unless  (my $f = fork)
    {
        # exit if (defined $q->param('jobID'));
        #close (STDERR);
        #close (STDOUT);
        #close (LOG);
        #$self->dbh->disconnect;
        #$self->{dbh} = undef;
        #open STDERR;
        if (!defined $q->param('jobID')) {
            $self->align_sequences_and_create_job($jobID);
        }

        print STDERR "ALIGNMENT FINISHEd\n";
    }
    #else
    {
        $q->param(jobID    => $jobID);
        $q->param(analysis => 'ALIGNMENT');
        return $self->matrixSelectionForm();
    }
}

sub t_select_ttf_after_ortholog_fetch  {
    my $self = shift;
    my $q = $self->query;

    my $jobID = $self->{job}->jobID;
    $q->param(jobID    => $jobID);
    $q->param(analysis => 'ALIGNMENT');
    return $self->matrixSelectionForm();
}


sub t_searchform  {

    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("generic_no_job.html",
                                    die_on_bad_params => 0 );
    $template->param( %{$self->{'params'}} );
    my $REL_CGI_BIN_DIR = $self->{env}->param("REL_CGI_BIN_DIR");
    $template->param
        ('TITLE' => "Search for human: mouse ortholog pair",
         'TITLE_IMG'=> "get_names.gif",
          'CAPTION' => "Search for a gene to retrieve human and mouse orthologous
                     sequences for.",
           'CONTENT' => qq*
            <form action="$REL_CGI_BIN_DIR/consite"  method="GET"><font color="black">
              <div align="left">

                <input type="hidden" name="rm" value="t_genesearch" >
                Enter one or more terms separated by spaces.<br>
                <input size="40" name="querystring">
                <input type="submit" width="40" value="Go" name="submit">
                <input name="Clear" type="reset" width="40" value="Clear">
                <br>
                <font size="-1"><i>Combine terms with:</i>&nbsp;
                <input type="radio" name="querybool" checked value="AND">
                &nbsp;AND &nbsp;
                <input type="radio" name="querybool" value="OR">
                &nbsp;OR<br>
                <input type="checkbox" name="filter" checked>
                &nbsp; <i>Exclude low-scoring hits</i></font>
              </div></font>
            </form>
	                 *,

         %LAYOUT_PARAMS,
          );


    return $template->output();
}

sub t_genesearch  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("generic_no_job.html",
                                    die_on_bad_params =>0 );
    $template->param( %{$self->{'params'}},
                        'TITLE_IMG'=> "get_genes.gif",
                        'CAPTION' => "Select a gene pair from the list.",
                    );
    my $page = ConSNPWeb::Page::GeneLynxSearchResult->new
                                        ( template => $template,
                                         row_color => "#ffffcf");
    $page->output;

}

sub t_select_relative_genomic_seq  {
    my $self = shift;
    my $q = $self->query();
    my $template = $self->load_tmpl("generic_no_job.html",
                                    die_on_bad_params =>0 );
    $template->param( %{$self->{'params'}} ,
                        'TITLE_IMG'=> "get_transcripts.gif",
                        'CAPTION' => "Select a pair of reference transcripts from the mRNA sequences mapped to the selected genes
to define the transcription start site and retrieve promoter sequences to analyze."
                     );
    my $page = ConSNPWeb::Page::SelectRelativeGenomicSeq->new
                                        ( template => $template);
    $page->output;

}


sub matrixSelectionForm  {

    my $self = shift;
    my $q = $self->query;
    #print STDERR "PRIJE PICKERA\n";
    my $tfp = CONSITE::TFpicker->new($self->dbh);
    my $template = $self->load_tmpl("select.html",
				    die_on_bad_params =>0 );
    $template->param( %{$self->{params}} );

    #print STDERR "IZA TEMPLATE\n";

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
    elsif ($q->param('select_by') eq "upload_list")  {
        $template->param('SELECTION_TABLE' => $tfp->upload_list,
                         'UPLOAD_LIST' => 1);
    }
    else  {
        $template->param('SELECTION_TABLE' => $tfp->name_table());
    }

    $template->param
	    ('HIDDEN' =>
            $q->hidden( -name=>"rm",
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
    my ($seq1, $header1) = $self->getSequence(  $q->param('seq1'),
                                                $q->param('seq1acc'),
                                                $q->param('seq1fh'),
                                                $q->param('seq1name')
                            );
    my ($seq3, $header3) = $self->getSequence(  $q->param('seq3'),
                                                $q->param('seq3acc'),
                                                $q->param('seq3fh'),
                                                $q->param('seq3name')
                            );

    ($header1,  $header3) =(($header1 or "Seq1"),
                            ($header3 or "Ref_cDNA")
                                    );
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

    #print STDERR "/nTOCKA 5/n";
    # create job object

    my $job = CONSITE::Job->new(-jobID=>$jobID,
				-seq1 =>$seqobj1,
				-seq3 =>$seqobj3,
				-tmpdir => ABS_TMP_DIR);

    # add strands to job
    #$job->tmp_dir(ABS_TMP_DIR);
    $job->strand1($strand1);
    $job->strand3($strand3);
    $job->strandref($q->param('strandref') or 1);
    $job->exclude_orf($q->param('exclude_orf')
		       or 0);

    # store job on disk


    Persistence::Object::Simple->commit( __Fn=>ABS_TMP_DIR."/".$jobID,
					 Data=>$job);


}


sub create_job_readyaln  {

    my ($self, $jobID) = @_;
    my $q = $self->query();
    my $output = "";
    my ($seq3, $header3) = $self->getSequence($q->param('seq3'),
			   $q->param('seq3acc'),
			   $q->param('seq3fh'),
               $q->param('seq3name')
			   );
    $header3 = "Ref_cDNA" unless $header3;
    my $FH = ($q->param('alignFH') or $self->throw("No alignment filehandle provided"));
    my $alignstring;

    my $alnIN = Bio::AlignIO->new(-fh => $FH,
			   -format => ($q->param("alnformat") or "clustalw"));
    my $alignobj;
    eval { $alignobj = $alnIN->next_aln; };
    if ($@ or !$alignobj) {
        return "Error parsing the alignment file. Make sure that the file is OK and that you have chosen the correct format.\n\n".$@;

    }

    {
        my $alnOUT = Bio::AlignIO->new(-fh => IO::String->new($alignstring),
                       -format => "clustalw");
        $alnOUT->write_aln($alignobj);
        $alnOUT->close;
    }

    my ($seqobj1, $seqobj2) =
	$self->_seqobjs_from_alignobj($alignobj);
    my $strand1 = 1; # plus by default
    my $strand2 = 1; # plus by default
    my $strand3;     # is returned by _find_exons below

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

    print STDERR "JOBID1:".$jobID."\n\n";

    print STDERR "SEQOBJ1:".$seqobj1->seq."\n\n";
    print STDERR "SEQOBJ2:".$seqobj2->seq."\n\n";
    #print STDERR "ALIGNSTRING:".$alignstring."\n\n";

    # create job object

    my $job = CONSITE::Job->new(-jobID=>$jobID,
				-seq1 =>$seqobj1,
				-seq2 =>$seqobj2,
				-seq3 =>$seqobj3,
				-alignstring => $alignstring);

    # add strands to job
    $job->tmpdir(ABS_TMP_DIR);
    $job->strand1($strand1); $job->strand2($strand2); $job->strand3($strand3);
    $job->strandref($q->param('strandref') or 1);
    $job->exclude_orf($q->param('exclude_orf')
		       or 0);

    # store job on disk

    Persistence::Object::Simple->commit( __Fn=>$job->tmpdir()."/".$jobID,
					 Data=>$job);

    return 0; # OK
}

sub _seqobjs_from_alignobj  {
    my ($self, $alignobj) = @_;
    my ($locseq1, $locseq2) = $alignobj->each_seq;
    my $seqobj1 =  Bio::Seq->new(-seq => _strip_gaps($locseq1->seq),
				 -id  => $locseq1->display_id);
    my $seqobj2 =  Bio::Seq->new(-seq => _strip_gaps($locseq2->seq),
				 -id  => $locseq2->display_id);
    return ($seqobj1, $seqobj2);

}


sub _seqobjs_from_clustal_old  {
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
    $seq =~ s/\W//g;
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

    # prepare and run alignment program

    my ($seq1, $header1) = $self->getSequence(  $q->param('seq1'),
                                                $q->param('seq1acc'),
                                                $q->param('seq1fh'),
                                                $q->param('seq1name')
                            );
    my ($seq2, $header2) = $self->getSequence(  $q->param('seq2'),
                                                $q->param('seq2acc'),
                                                $q->param('seq2fh'),
                                                $q->param('seq2name')
                            );
    my ($seq3, $header3) = $self->getSequence(  $q->param('seq3'),
                                                $q->param('seq3acc'),
                                                $q->param('seq3fh'),
                                                $q->param('seq3name')
                            );

    ($header1, $header2, $header3) =(($header1 or "Seq1"),
                                     ($header2 or "Seq2"),
                                     ($header3 or "Ref_cDNA")
                                    );
    $header1 =~ s/ /_/g; $header2 =~ s/ /_/g; $header3 =~ s/ /_/g;

    $output .= $q->p([$seq1, $seq2, $header1, $header2])
	if $DEBUG;

    my $strand1 = 1; # plus by default
    my $strand3;     # is returned by _find_exons below
    my ($alignstring, $strand2);
    my $alignment_program = ($q->param("alignprog") or ALIGNMENT_PROGRAM);
    if ($alignment_program != "DBP" and $alignment_program !="ORCA")  {
	    $self->ExitError("No valid alignment program found: ".ALIGNMENT_PROGRAM);

    }
    else  {
        if (my $f = fork)  {
            $self->{dbh} = undef;
            if ($alignment_program eq "DPB") {
            ($alignstring, $strand2) =
                DPB_remote($seq1, $seq2, $header1, $header2);
            }
            elsif ($alignment_program eq "ORCA") {
            ($alignstring, $strand2) =
                $self->ORCA_local($seq1, $seq2, $header1, $header2);

            }

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


            Persistence::Object::Simple->commit( __Fn=>ABS_TMP_DIR."/".$jobID,
                             Data=>$job);
        }
    }

}

sub _find_orf  {
    my ($self, $cdnaobj) = @_;
    my ($cdnaFH, $cdnafile) = tempfile(DIR=>ABS_TMP_DIR);
    # print STDERR "cDNA FILE $cdnafile\n";
    my $outfile = ABS_TMP_DIR."/papak.out";
    Bio::SeqIO->new(-fh=>$cdnaFH, -format=>"Fasta")->write_seq($cdnaobj);
    close $cdnaFH;
    my @args = split /\s+/,
              "/usr/local/bin/getorf -methionine 1 -sequence $cdnafile -outseq $outfile";
    system(@args)==0 or (print STDERR "System call failed:$?"); #wait;
    my @outlines = split("\n", `grep '>' $outfile`);
    # print STDERR ("\nOUTFILE:",`grep '>' $outfile`);
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

#    my $set = $self->dbh->get_MatrixSet
#        (-IDs=> [$self->{job}->IDlist()],
#         -matrixtype=>"PWM"
#         ) ;

    my $set = $self->get_MatrixSet();

    my %singleseq_params =
	(-job         => $self->{job}, # this is temporary
	 -window      => $self->{job}->window(),
	 -cutoff      => $self->{job}->cutoff(),
	 -MatrixSet   => $set,
	 -rel_tmp_dir => REL_TMP_DIR,
	 -abs_tmp_dir => ABS_TMP_DIR,
	 -rel_cgi_bin_dir => REL_CGI_BIN_DIR);
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

#      my $set = $self->dbh->get_MatrixSet
#          (-IDs=> [$self->{job}->IDlist()],
#           -matrixtype=>"PWM"
#           );
    print STDERR "In create_alignobject:prije \n \n";

    my $set = $self->get_MatrixSet();
    print STDERR "In create_alignobject:\n $set\n";

    my %alignment_params =
	(-job         => $self->{job}, # this is temporary
	 -alignstring => $self->{job}->alignstring,
	 -window      => $self->{job}->window(),
	 -cutoff      => $self->{job}->cutoff()."",
	 -seqobj1     => $self->{job}->seq1(),
	 -MatrixSet   => $set,
	 -rel_tmp_dir => REL_TMP_DIR,
	 -abs_tmp_dir => ABS_TMP_DIR,
	 -rel_cgi_bin_dir => REL_CGI_BIN_DIR );

    print STDERR Data::Dumper::Dumper(%alignment_params);

    if (!defined($q->param('select_by'))
	and defined $q->param('start_at')
	and defined $q->param('end_at'))
    {
	%alignment_params =
	    ( %alignment_params,
	      -start    => $q->param('start_at'),
	      -end      => $q->param('end_at') );
    }
    print STDERR "In create_alignobject:before aln \n \n";
    my $aln = CONSITE::Alignment->new(%alignment_params);
    print STDERR "In create_alignobject:after aln \n \n";
    return $aln;
    #$self->{job}->alignobject($aln);

}

sub get_MatrixSet  {
    my $self = shift;
    print STDERR "Entered get_Matrixset (no user matrix)\n:\n";
    # this sub has to take into account the possibility that
    # a matrix set can either come from a database, retrieved by
    # $self->{job}->IDlist(), OR from a single, user-defined matrix

    my $set;
    if (defined $self->{job}->user_matrix())  {
	$set = $self->{job}->user_matrix->get_MatrixSet(-matrixtype=>"PWM");
    }
    else  {
	print STDERR $self->{job}->IDlist;
	$set = $self->dbh->get_MatrixSet

        (-IDs=> [$self->{job}->IDlist()],
         -matrixtype=>"PWM"
         );
	#print STDERR "in get_Matrixset (no user matrix)\n: ".keys(%$set)."\n"
    }
    print STDERR "returning from get_MatrixSet:";
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
    my ($self, $seq, $acc, $fh, $header) = @_;

    my $seqstring = "";

    if ($seq)  {
        $seqstring=$self->parseSequence ($seq) or $self->ExitError ("Error parsing sequence.");
    }
    elsif ($acc)  {
        use Bio::Seq;
        use Bio::DB::GenBank;
        my $gb=new Bio::DB::GenBank;
        my $seqobj= new Bio::Seq;
        eval {$seqobj=$gb->get_Seq_by_acc($acc) };
        if ($@ or !$seqobj)  {
            $self->ExitError("Could not retrieve nucleotide sequence ".
                  "with the accession number ".
                  "<B>".$acc."</B>. ".
                  " Check the accession number or try again later.");
        }
        $seqstring=$seqobj->seq();
        $header = $seqobj->display_id unless $header;
    }
    elsif ($fh) {
        my $rawseq;
        my $FILEHANDLE=$fh or die;
        while (my $line = <$FILEHANDLE>) {
            $rawseq .=$line;
        }
        # print $rawseq;
        $seqstring=$self->parseSequence ($rawseq)
            or $self->ExitError ("Error parsing uploaded sequence.");
    }
    else {
        return undef;
    }
    # truncate if too big

    if  (length($seq) > MAX_SEQ_LENGTH) {
        $seqstring = substr($seqstring, 0, MAX_SEQ_LENGTH);
    }

    return ($seqstring, $header);
}



sub parseSequence  {
    my ($self,$rawseq) = @_;
    #print "<p>RAWSEQ: $rawseq</p>";
    my @lines=split("\n", $rawseq);
    my $seq = "";
    foreach my $line (@lines)  {
        $line =~ s/^\s+//;
        $line =  uc($line);
        if ($line =~ /^>/)  {
            last if $seq;
        }
        else  {
            $line =~ s/[\s+|\d+]//g;
            ValidateSeq($line, 'N')
            or $self->ExitError
                ("Illegal character(s) in nucleotide query sequence, ".
                 "line:<BR>$line");
            $seq .=$line;
        }
    }

    if ($seq) { return $seq}
    else      { $self->ExitError ("No sequence provided.") }

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
    my ($self, $errormsg) = (@_);

    print CGI::header, CGI::start_html,"ERROR",$errormsg,CGI::end_html;
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
		    header2 => $header2.""
		    ] );

    my @alignment_lines =
	split "\n", $response->content;

    print STDERR "SEQ1 $seq1\n";
    print STDERR "SEQ2 $seq2\n";
    print STDERR "HEADER1 $header1\n";
    print STDERR "HEADER2 $header2\n";
    # print STDERR $response->content;

    my $strand = pop (@alignment_lines);
    if ($strand eq "FAILED")  {

        # DPB crash handling instruction goes here
        ExitError ("", "DPB alignment program has failed to produce ".
            "an alignment of your input sequences. ".
            "An error report has been sent to the administrator of the site");


    }
    unless ($strand==1 or $strand==-1) {
        push @alignment_lines, $strand;
        $strand=1;
    }
    my $alignment = join("\n", @alignment_lines);
    # print STDERR ">>>ALIGNMENT: $alignment";
    return ($alignment, $strand);
}

sub ORCA_local  {
    my ($self, $seq1, $seq2, $header1, $header2) = @_;
    my $orca = Orca->new;
    my $alignobj = $orca->Align(-seq1 => Bio::Seq->new(-id =>$header1,
						       -seq=>$seq1),
				-seq2 => Bio::Seq->new(-id =>$header2,
						       -seq=>$seq2));

    my $alignstring;
    my $fh = IO::String->new($alignstring);
    my $alnIO = Bio::AlignIO->new(-fh => $fh, -format => "clustalw");
    $alnIO->write_aln($alignobj);
    $alnIO->close;
    print STDERR "ALIGNSTRING: $alignstring";
    return($alignstring, 1);
}


sub ORCA_local_old  {
    my ($self, $seq1, $seq2, $header1, $header2) = @_;
    my ($tempseqfile1, $tempseqfile2) =
	(ABS_TMP_DIR."/".int(rand(1000000)).".seq1.fa",
	 ABS_TMP_DIR."/".int(rand(1000000)).".seq2.fa");
    _write_seq_from_string($tempseqfile1, $header1, $seq1);
    _write_seq_from_string($tempseqfile2, $header2, $seq2);
    my $orcaexec = ORCA_BINARY;
    my $alignstring =
	`/usr/bin/perl $orcaexec -in1 $tempseqfile1 -in2 $tempseqfile2 -format clustalw`;
    print STDERR $?;
    print STDERR "ALIGNSTRING: $alignstring";
    #unlink $tempseqfile1;  unlink $tempseqfile2;
    return ($alignstring, 1);

}

sub _write_seq_from_string {
    my ($file,  $header, $seqstring) = @_;
    my $ostream = Bio::SeqIO->new(-file=>">$file",
				   -format=>"fasta");
    $ostream->write_seq(Bio::Seq->new(-id=>$header,
				       -seq=>$seqstring,
				       -alphabet=>"dna")
			);
    $ostream->close;

}



sub _clean_tempfiles  {
    my @tempfiles = glob (ABS_TMP_DIR."/*");
    foreach my $file (@tempfiles)  {
	unlink $file if -M $file > CLEAN_TEMPFILES_OLDER_THAN;
    }
}

sub dbh  {
    my $self = shift;
    return $self->{'dbh'};
}

sub _map_to_coord {
    my ($map, $relstart, $relend, $relative_to) = @_;
    my ($absstart, $absend, $strand, $chr);
    my $zero_pos_correction = 0;
    if ($relstart*$relend <0) {
        $zero_pos_correction = 1;
    }
    if ($relative_to eq "3prime") {

        if ($map->strand eq "-" or $map->strand eq "-1") {
            $absstart = $map->tStart - $relend;
            $absend = $map->tStart - $relstart -$zero_pos_correction;
            $strand = "-";
        }
        else {
            $absstart = $map->tEnd + $relstart + $zero_pos_correction;
            $absend = $map->tEnd + $relend;
            $strand = "+";
        }

    }
    else {

        if ($map->strand eq "-" or $map->strand eq "-1") {
            $absstart = $map->tEnd - $relend;
            $absend = $map->tEnd - $relstart- $zero_pos_correction;
            $strand = "-";
        }
        else {
            $absstart = $map->tStart + $relstart + $zero_pos_correction;
            $absend = $map->tStart + $relend;
            $strand = "+";
        }
    }
    $chr = $map->tName;
    $chr =~ s/chr//;
    return (start  => $absstart,
            end    => $absend,
            chr    => $chr,
            strand => $strand);
}


1;
