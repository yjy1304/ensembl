package XrefMapper::danio_rerio;

use  XrefMapper::BasicMapper;

use vars '@ISA';

@ISA = qw{ XrefMapper::BasicMapper };

sub set_display_xrefs{
  my $self = shift;
  my $display = XrefMapper::DisplayXrefs->new($self);
  $display->set_display_xrefs_from_stable_table();

}

sub set_gene_descriptions(){
  my $self = shift;
  my $display = XrefMapper::DisplayXrefs->new($self);
  $display->set_gene_descriptions_from_display_xref()
}

sub get_official_name{
   return "ZFIN_ID";
}

sub get_canonical_name{
   return "ZFIN_ID";
}

# Not running transcript_names_from_gene for merged species
# as this is already been done in the OfficialNaming mapper
sub transcript_names_from_gene {
  return;
}


sub species_specific_pre_attributes_set{
  my $self  = shift;
  $self->official_naming();
}

sub species_specific_cleanup{
  my $self = shift;
  my $dbname = $self->get_canonical_name;

  print "Removing all $dbname from object_xref not on a Gene\n";
  my $remove_old_ones = (<<JSQL);
delete ox
  from object_xref ox, xref x, external_db e
    where e.db_name like "$dbname" and
          ox.ensembl_object_type != "Gene" and
          ox.xref_id = x.xref_id and
          x.external_db_id = e.external_db_id;
JSQL

  #
  # First Delete all the hgnc object_xrefs not on a gene. (i.e these are copys).
  #

  my $sth = $self->core->dbc->prepare($remove_old_ones);

  $sth->execute() || die "Could not execute: \n$remove_old_ones \n";

  $sth->finish;

}

sub gene_description_sources {

  return ("RFAM",
	  "miRBase",
          "ZFIN_ID",
          "IMGT/GENE_DB",
	  "Uniprot/SWISSPROT",
	  "RefSeq_peptide",
	  "RefSeq_dna",
	  "Uniprot/Varsplic",
	  "Uniprot/SPTREMBL");

}


1;
