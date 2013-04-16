package XrefParser::miRBaseParser;

use strict;
use warnings;
use Carp;
use DBI;

use base qw(XrefParser::BaseParser);


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

  if(!defined($species_id)){
    $species_id = $self->get_species_id_for_filename($file);
  }

  my $xrefs = $self->create_xrefs($source_id, $file, $species_id);
  if(!defined($xrefs)){
    return 1; #error
  }
  # upload
  if(!defined($self->upload_xref_object_graphs($xrefs))){
    return 1; 
  }
  return 0; # successfull

}

# --------------------------------------------------------------------------------
# Parse file into array of xref objects

sub create_xrefs {

  my ($self, $source_id, $file, $species_id) = @_;

  my %species2name = $self->species_id2name();
  my @names   = @{$species2name{$species_id}};

  my %name2species_id     = map{ $_=>$species_id } @names;

  my $file_io = $self->get_filehandle($file);
  if ( !defined $file_io ) {
    print STDERR "ERROR: Could not open $file\n";
    return 1;    # 1 is an error
  }

  my @xrefs;

  local $/ = "\n\/\/";

  while ($_ = $file_io->getline()) {

    my $xref;

    my $entry = $_;
    chomp $entry;

    next if (!$entry);

    my ($header, $sequence) = split (/\nSQ/, $entry, 2);
    # remove newlines
    my @seq_lines = split (/\n/, $sequence) if ($sequence);
    # drop the information line
    shift @seq_lines;
    # put onto one line
    $sequence = join("", @seq_lines);
    # make uppercase
    $sequence = uc($sequence);
    # replace Ts for Us
    $sequence =~ s/U/T/g;
    # remove numbers and whitespace
    $sequence =~ s/[\d+,\s+]//g;

#    print "$header\n";
    my ($name) = $header =~ /\nID\s+(\S+)\s+/;
    my ($acc) = $header =~ /\nAC\s+(\S+);\s+/;
    my ($description) = $header =~ /\nDE\s+(.+)\s+stem-loop/;
    my @description_parts = split (/\s+/, $description) if ($description);
    # remove the miRNA identifier
    pop @description_parts;
    my $species =  join(" ", @description_parts);
    $xref->{SEQUENCE_TYPE} = 'dna';
    $xref->{STATUS} = 'experimental';
    $xref->{SOURCE_ID} = $source_id;
    $species = lc $species;
    $species =~ s/ /_/;
    
    my $species_id_check = $name2species_id{$species};


    next if (!defined($species_id_check));
    
    # skip xrefs for species that aren't in the species table
    if (defined($species_id) and $species_id == $species_id_check) {
      
      $xref->{ACCESSION} = $acc;
      $xref->{LABEL} = $name;
      $xref->{DESCRIPTION} = $name;
      $xref->{SEQUENCE} = $sequence;
      $xref->{SPECIES_ID} = $species_id;

      # TODO synonyms, dependent xrefs etc
      push @xrefs, $xref;
    }
  }

  $file_io->close();

  print "Read " . scalar(@xrefs) ." xrefs from $file\n";
 
  return \@xrefs;

}


1;
