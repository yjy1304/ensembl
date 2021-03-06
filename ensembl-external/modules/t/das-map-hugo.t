=head2 DESCRIPTION

This test covers the following DAS conversions:
  hugo_gene -> ensembl_peptide
  hugo_gene -> chromosome

=cut
use strict;

BEGIN { $| = 1;
	use Test::More tests => 14;
}

use Bio::EnsEMBL::ExternalData::DAS::Coordinator;
# TODO: need to use data from a test database!
#use Bio::EnsEMBL::Test::MultiTestDB;
#use Bio::EnsEMBL::Test::TestUtils;
#my $multi = Bio::EnsEMBL::Test::MultiTestDB->new();
#my $dba = $multi->get_DBAdaptor( 'core' );
use Bio::EnsEMBL::Registry;
Bio::EnsEMBL::Registry->load_registry_from_db(
  -host => 'ensembldb.ensembl.org',
  -user => 'anonymous',
);
my $dba = Bio::EnsEMBL::Registry->get_DBAdaptor( 'human', 'core' ) || die("Can't connect to database");

use Bio::EnsEMBL::Utils::Exception qw(verbose);
verbose('EXCEPTION'); # we are deliberately instigating warnings

my $pea = $dba->get_TranslationAdaptor();
my $gea = $dba->get_GeneAdaptor();
my $tra = $dba->get_TranscriptAdaptor();
my $sla = $dba->get_SliceAdaptor();
my $prot = $pea->fetch_by_stable_id('ENSP00000324984');
my $tran = $tra->fetch_by_translation_stable_id($prot->stable_id);
my $gene = $gea->fetch_by_translation_stable_id($prot->stable_id);
my $chro = $sla->fetch_by_transcript_stable_id($tran->stable_id);
$gene = $gene->transfer($chro);

my ($xref) = grep {$_->primary_id eq '24729'} @{ $gene->get_all_DBEntries('HGNC') };
my $prot_cs = Bio::EnsEMBL::ExternalData::DAS::CoordSystem->new( -name => 'ensembl_peptide' );
my $xref_cs = Bio::EnsEMBL::ExternalData::DAS::CoordSystem->new( -name => 'hgnc' );
my $chro_cs = $chro->coord_system;

my $desc = 'hugo->peptide positional';
my $c = Bio::EnsEMBL::ExternalData::DAS::Coordinator->new();
my $segments = $c->_get_Segments($xref_cs, $prot_cs, undef, undef, $prot);
ok((grep {$_ eq $xref->primary_id} @$segments), "$desc correct query segment");
{
my $q_feat = &build_feat($xref->primary_id, 1, 1);
my $f = $c->map_Features([$q_feat], $xref_cs, $prot_cs, undef)->[0];
ok(!defined $f, "$desc did NOT get mapped feature");
}

$desc = 'hugo->peptide non-positional';
$c = Bio::EnsEMBL::ExternalData::DAS::Coordinator->new();
$segments = $c->_get_Segments($xref_cs, $prot_cs, undef, undef, $prot);
ok((grep {$_ eq $xref->primary_id} @$segments), "$desc correct query segment");
SKIP: {
my $q_feat = &build_feat($xref->primary_id, 0, 0);
my $f = $c->map_Features([$q_feat], $xref_cs, $prot_cs, undef)->[0];
ok($f, "$desc got mapped feature") || skip('requires mapped feature', 3);
is($f->start,  0,  "$desc correct start");
is($f->end,    0,    "$desc correct end");
is($f->strand, 1, "$desc correct strand");
}

my $desc = 'hugo->chromosome positional';
my $c = Bio::EnsEMBL::ExternalData::DAS::Coordinator->new();
my $segments = $c->_get_Segments($xref_cs, $chro_cs, $chro, undef, undef);
ok((grep {$_ eq $xref->primary_id} @$segments), "$desc correct query segment");
{
my $q_feat = &build_feat($xref->primary_id, 1, 1);
my $f = $c->map_Features([$q_feat], $xref_cs, $chro_cs, undef)->[0];
ok(!defined $f, "$desc did NOT get mapped feature");
}

$desc = 'hugo->chromosome non-positional';
$c = Bio::EnsEMBL::ExternalData::DAS::Coordinator->new();
$segments = $c->_get_Segments($xref_cs, $chro_cs, $chro, undef, undef);
ok((grep {$_ eq $xref->primary_id} @$segments), "$desc correct query segment");
SKIP: {
my $q_feat = &build_feat($xref->primary_id, 0, 0);
my $f = $c->map_Features([$q_feat], $xref_cs, $chro_cs, undef)->[0];
ok($f, "$desc got mapped feature") || skip('requires mapped feature', 3);
is($f->start,  0,  "$desc correct start");
is($f->end,    0,    "$desc correct end");
is($f->strand, 1, "$desc correct strand");
}

sub build_feat {
  my ($segid, $start, $end, $strand ) = @_;
  return {
    'segment_id'  => $segid,
    'start'       => $start,
    'end'         => $end,
    'orientation' => defined $strand && $strand == -1 ? '-' : '+',
  };
}