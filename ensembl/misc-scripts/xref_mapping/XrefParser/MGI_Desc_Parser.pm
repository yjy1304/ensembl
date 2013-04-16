package XrefParser::MGI_Desc_Parser;

use strict;
use warnings;
use Carp;
use File::Basename;

use base qw( XrefParser::BaseParser );

use Bio::EnsEMBL::DBSQL::DBAdaptor;


sub run {

  my ($self, $ref_arg) = @_;
  my $source_id    = $ref_arg->{source_id};
  my $species_id   = $ref_arg->{species_id};
  my $files        = $ref_arg->{files};
  my $verbose      = $ref_arg->{verbose};

  if((!defined $source_id) or (!defined $species_id) or (!defined $files) ){
    croak "Need to pass source_id, species_id and files as pairs";
  }
  $verbose |=0;

  my $file = @{$files}[0];

  my $mgi_io = $self->get_filehandle($file);

  if ( !defined $mgi_io ) {
    print STDERR "ERROR: Could not open $file\n";
    return 1;    # 1 is an error
  }

  my $xref_count =0;
  my $syn_count = 0;
  my %acc_to_xref;


    my $header = $mgi_io->getline(); #discard header line

    chomp($header);
    # crude emergency check for potentially altered file format.
    my $header_template = qq(MGI Accession ID\tChr\tcM Position\tgenome coordinate start\tgenome coordinate end\tstrand\tMarker Symbol\tStatus\tMarker Name\tMarker Type\tFeature Type\tMarker Synonyms (pipe-separated));
    if ($header ne $header_template) {die "File header has altered from format parser expects. Check MGI "};
      
    while ( my $line = $mgi_io->getline() ) {

        chomp($line);
        my ($accession, $chromosome, $position, $start, $end, $strand,$label, 
            $status, $marker, $marker_type, $feature_type, $synonym_field) = split(/\t/,$line);
            
        $position =~ s/^\s+// if ($position);

        my @synonyms = split(/\|/,$synonym_field) if ($synonym_field);
        
	
        my $desc;
	if ($marker) {
	    $desc = $marker;
	}
        
        $acc_to_xref{$accession} = $self->add_xref({ acc        => $accession,
    	                           		             label      => $label,
    					                             desc       => $desc,
    					                             source_id  => $source_id,
    					                             species_id => $species_id,
    					                             info_type  => "MISC"} );
        if($verbose and !$desc){
    	   print "$accession has no description\n";
        }
        $xref_count++;
            
        if(defined($acc_to_xref{$accession})){
           
            foreach my $syn (@synonyms) {
                $self->add_synonym($acc_to_xref{$accession}, $syn);
                $syn_count++;
            }
            
        }
        
    }
      
    $mgi_io->close();
      
    print $xref_count." MGI Description Xrefs added\n" if($verbose);
    print $syn_count." synonyms added\n" if($verbose);

    return 0; #successful
}
	



1;

