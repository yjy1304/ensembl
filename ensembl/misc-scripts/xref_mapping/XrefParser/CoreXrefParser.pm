package XrefParser::CoreXrefParser;

use strict;
use warnings;
use Carp;
use DBI;

use base qw( XrefParser::BaseParser );
use Bio::EnsEMBL::Registry;

sub run_script {

  my ($self, $ref_arg) = @_;
  my $source_id    = $ref_arg->{source_id};
  my $species_id   = $ref_arg->{species_id};
  my $file         = $ref_arg->{file};
  my $verbose      = $ref_arg->{verbose};

  if((!defined $source_id) or (!defined $species_id) or (!defined $file) ){
    croak "Need to pass source_id, species_id and file as pairs";
  }
  $verbose |=0;

  my $logic_name;
  my $biotype;
  my $object_type;
  my $project;
  my $copy_description_from_object;

  if($file =~ /logic_name[=][>](\S+?)[,]/){
    $logic_name = $1;
  }
  if($file =~ /biotype[=][>](\S+?)[,]/){
    $biotype = $1;
  }
  if($file =~ /object_type[=][>](\S+?)[,]/){
    $object_type = $1;
  }
  if($file =~ /project[=][>](\S+?)[,]/){
    $project = $1;
  }
  if($file =~ /copy_description_from_object[=][>](\S+?)[,]/){
    $copy_description_from_object = $1;
  }

  my $external_db_name = $self->get_source_name_for_source_id($source_id);

  #copy object xrefs from core

  my $registry = "Bio::EnsEMBL::Registry";

  if ($project eq 'ensembl') {
      $registry->load_registry_from_multiple_dbs( 
	  {
	      '-host'    => 'ens-staging1',
	      '-user'    => 'ensro',
	  },
	  {
	      '-host'     => 'ens-staging2',
	      '-user'     => 'ensro',
	  },
       );
  } elsif ($project eq 'ensemblgenomes') {

      $registry->load_registry_from_multiple_dbs( 
	  {
	      '-host'     => 'mysql-eg-staging-1.ebi.ac.uk',
	      '-port'     => 4160,
	      '-user'     => 'ensro',
	  },
	  {
	      '-host'     => 'mysql-eg-staging-2.ebi.ac.uk',
	      '-port'     => 4275,
	      '-user'     => 'ensro',
	  },
      );

  } else {
      die("Missing or unsupported project value. Supported values: ensembl, ensemblgenomes");
  }

  #get the species name
  my %id2name = $self->species_id2name;
  my $species_name = $id2name{$species_id}[0];

  if (!$object_type) {
      $object_type = 'gene';
  }

  my %valid_object_types = (

      gene => 'Gene',
      transcript => 'Transcript',
      translation => 'Translation',
      Gene => 'Gene',
      Transcript => 'Transcript',
      Translation => 'Translation',
  );

  if (!exists($valid_object_types{$object_type}) ) {

      die("Unsupported object type value. Supported values: ", join(',', keys %valid_object_types) );
  }

  if ($biotype &&  $object_type ne 'gene' && $object_type ne 'transcript') {
      die("Incorrect parser argument values: expecting gene or transcript object type when biotype provided.\n");
  }

  my $object_adaptor = $registry->get_adaptor($species_name, 'core', $object_type);

  my @genes;

  if ($verbose) {
      print STDERR "fetching genes...\n";
  }
  
  if ($biotype) {
      @genes = @{$object_adaptor->fetch_all_by_biotype($biotype)};
      if ($biotype eq "tRNA") {
	  # Fetch also all tRNA_pseudogene genes
	  push (@genes, @{$object_adaptor->fetch_all_by_biotype('tRNA_pseudogene')});
      }
  } elsif ($logic_name) {

      if ($verbose) {
	  print STDERR "Fetching by logic_name, $logic_name\n";
      }

      # This way we get all ncRNA genes (rRNAs, tRNAs, and all ncRNAs which can be under multiple biotypes)

      @genes = @{$object_adaptor->fetch_all_by_logic_name($logic_name)};
  }
  
  my %added_xref;
  my $direct_count = 0;

  print STDERR "Fetched " . @genes . " genes\n";

  foreach my $object (@genes) {

      #my @xrefs = @{$object->get_all_DBEntries($external_db_name)};
      # as we use a generic ncRNA source, which maps to multiple external_db_id
      my @xrefs = @{$object->get_all_DBEntries()};

      # print STDERR "processing " . @xrefs . " xrefs\n";

      if (@xrefs == 0) {
	  print STDERR "No xrefs for gene, " . $object->stable_id() . "!\n";
      }

      foreach my $xref (@xrefs) {

	  my $xref_id;
	  my $db_name = $xref->dbname();

	  # $source_id maps to nCRNA_EG
	  # but we need to attach them specifcally
	  # to RNAmmer, tRNAScan or RFAM
	  # so get the source based on the db_name from the core db
	  my $external_source_id = $self->get_source_id_for_source_name($db_name);
	  
	  if (! defined $external_source_id) {
	      warn ("can't get a source_id for external_db, $db_name!\n");
	      return 1;
	  }
	  
	  if (!exists($added_xref{$xref->primary_id()})) {
	      
	      my $description = $xref->description();

	      if ($copy_description_from_object && !$description) {

		  if ($object->description()) {
                      #populate xref description with object description stripping the [Source: .. part
		      ($description) = $object->description() =~ /([^\[]+)/;
		      #trim trailing spaces
		      $description =~ s/\s+$//;
		  }
	      }
	      
	      $xref_id = $self->add_xref({ acc        => $xref->primary_id(),
				      version    => $xref->version(),
				      label      => $xref->display_id(),
				      desc       => $description,
				      source_id  => $external_source_id,
				      species_id => $species_id,
				      info_type  => "DIRECT"} );


	      $added_xref{$xref->primary_id()} = $xref_id;
	  } 

	  if (!$xref_id) {
	      $xref_id = $added_xref{$xref->primary_id()};
	  }
	  
	  $self->add_direct_xref($xref_id, $object->stable_id(), $valid_object_types{$object_type}, "");
	  $direct_count++;
      }
  }

  my $xref_count = scalar(keys %added_xref);

  print "Added $xref_count $external_db_name xrefs and $direct_count $object_type direct xrefs\n" if($verbose);
  if ( !$xref_count ) {
      return 1;    # 1 error
  }

  return 0; # successfull
 

}

1;
