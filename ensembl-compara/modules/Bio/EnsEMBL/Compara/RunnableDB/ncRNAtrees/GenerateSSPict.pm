#
# You may distribute this module under the same terms as perl itself
#

=pod

=head1 NAME

    Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::GenerateSSPict

=head1 DESCRIPTION

This Hive analysis will create secondary structure plots based on the
secondary structures (in bracket notation) created by Infernal.
In addition to secondary structure plots for the whole alignments 
of the family, plots for individual members are also created.

=head1 CONTACT

   Please email comments or questions to the public Ensembl
   developers list at <dev@ensembl.org>.

   Questions may also be sent to the Ensembl help desk at
   <helpdesk@ensembl.org>

=head1 APPENDIX

The rest of the documentation details each of the object methods.

Internal methods are usually preceded with an underscore (_)

=cut


package Bio::EnsEMBL::Compara::RunnableDB::ncRNAtrees::GenerateSSPict;

use strict;
use warnings;
use Data::Dumper;

use base ('Bio::EnsEMBL::Compara::RunnableDB::RunCommand', 'Bio::EnsEMBL::Compara::RunnableDB::BaseRunnable');


sub fetch_input {
    my ($self) = @_;

    $self->input_job->transient_error(0);
    my $nc_tree_id = $self->param('gene_tree_id') or $self->throw("A 'gene_tree_id' is mandatory");
    $self->input_job->transient_error(1);

    my $nc_tree = $self->compara_dba->get_GeneTreeAdaptor->fetch_by_dbID($nc_tree_id) or die "Could not fetch nc_tree with id=$nc_tree_id\n";
    $self->param('nc_tree', $nc_tree);

    my $model_name = $nc_tree->get_tagvalue('model_name');
    $self->param('model_name', $model_name);

    my $ss_cons = $nc_tree->get_tagvalue('ss_cons');
    $self->param('ss_cons', $ss_cons);

    my $input_aln = $self->_fetchMultipleAlignment();
    $self->param('input_aln', $input_aln);

    my $ss_model_picts_dir = $self->param('ss_picts_dir') . "/" . $model_name;
    mkdir($ss_model_picts_dir);
    $self->param('ss_model_picts_dir', $ss_model_picts_dir);

    return;
}

sub run {
    my ($self) = @_;

    $self->_dumpMultipleAlignment();
    $self->get_plot();
    return;
}

sub _fetchMultipleAlignment {
    my ($self) = @_;

    my $tree = $self->param('nc_tree');

    my $sa = $tree->get_SimpleAlign( -id => 'MEMBER' );
    return $sa;
}

sub _dumpMultipleAlignment {
    my ($self) = @_;
    my $aln = $self->param('input_aln');
    my $model_name = $self->param('model_name');
    my $ss_cons = $self->param('ss_cons');

    if ($ss_cons =~ /^\.d+$/) {
        $self->input_job->incomplete(0);
        die "tree " . $self->param('gene_tree_id') . " has no structure: $ss_cons\n";
    }

    my $ss_model_picts_dir = $self->param('ss_model_picts_dir');
    my $aln_filename = "${ss_model_picts_dir}/${model_name}.sto";

    print STDERR "ALN FILE IS: $aln_filename\n" if ($self->debug);

    open my $aln_fh, ">", $aln_filename or die $!;
    print $aln_fh "# STOCKHOLM 1.0\n";
    for my $aln_seq ($aln->each_seq) {
        printf $aln_fh ("%-20s %s\n", $aln_seq->display_id, $aln_seq->seq);
    }
    printf $aln_fh  ("%-20s\n", "#=GF R2R keep allpairs");
    printf $aln_fh  ("%-20s %s\n//\n", "#=GC SS_cons", $ss_cons);

    close($aln_fh);
    $self->param('aln_file', $aln_filename);
    return;
}

sub get_cons_aln {
    my ($self) = @_;
    my $aln_file = $self->param('aln_file');
    my $out_aln_file = $aln_file . ".cons";
    ## For information about these options, check http://breaker.research.yale.edu/R2R/R2R-manual-1.0.3.pdf";
    $self->run_r2r_and_check("--GSC-weighted-consensus", $aln_file, $out_aln_file, "3 0.97 0.9 0.75 4 0.97 0.9 0.75 0.5 0.1");
    return;
}

sub get_plot {
    my ($self) = @_;

    my $r2r_exe = $self->param('r2r_exe') || die "path to r2r is not specified\n";
    my $aln_file = $self->param('aln_file');
    my $tree = $self->param('nc_tree');

    my $out_aln_file = $aln_file . ".cons";
    $self->get_cons_aln();

    ## First we create the thumbnails
    my $meta_file_thumbnail = $aln_file . "-thumbnail.meta";
    my $svg_thumbnail_pic = "${out_aln_file}.thumbnail.svg";
    open my $meta_thumbnail_fh, ">", $meta_file_thumbnail or die $!;
    print $meta_thumbnail_fh "$out_aln_file\tskeleton-with-pairbonds\n";
    close($meta_thumbnail_fh);
    $self->run_r2r_and_check("", $meta_file_thumbnail, $svg_thumbnail_pic, "");

    my $meta_file = $aln_file . ".meta";
    ## One svg pic per member
    for my $member (@{$tree->get_all_Members}) {
        my $member_id = $member->name();
        open my $meta_fh, ">", $meta_file or die $!;
        print $meta_fh "$out_aln_file\n";
        print $meta_fh "$aln_file\toneseq\t$member_id\n";
        close($meta_fh);
        my $svg_pic_filename = "${out_aln_file}-${member_id}.svg";
        $self->run_r2r_and_check("", $meta_file, $svg_pic_filename, "");
    }
    return;
}

sub fix_aln_file {
    my ($self, $msg) = @_;

    my @columns = $msg =~ /\[(\d+),(\d+)\]/g;

    my $aln_file = $self->param('aln_file');
    open my $aln_fh, "<", $aln_file or die $!;
    my $label_line = sprintf("%-21s",   "#=GC R2R_LABEL");
    my $keep_line  = sprintf("%-21s\n", "#=GF R2R keep p");
    my $new_aln = "";
    while (<$aln_fh>) {
        $new_aln .= $_;
        chomp;
        if (/^#=GC\s+SS_cons\s+(.+)$/) {
            print STDERR "GC SS_CONS LINE: $_\n";
            my $cons_seq_len = length($1);
            $label_line .= "." x $cons_seq_len;
            for my $pos (@columns) {
                substr($label_line, $pos, 1, "p");
            }
            $new_aln .= "$label_line\n";
            $new_aln .= "$keep_line";
        }
    }
    close($aln_fh);
    open $aln_fh, ">", $aln_file or die $!;
    print $aln_fh $new_aln;
    close($aln_fh);
    $self->param('fixed_aln', 1);
    $self->get_cons_aln();
}

sub run_r2r_and_check {
    my ($self, $opts, $infile, $outfile, $extra_params) = @_;

    my $r2r_exe = $self->param('r2r_exe') || die "path to r2r is undefined\n";
    my $cmd = "$r2r_exe $opts $infile $outfile $extra_params";
    my $runCmd = $self->run_command($cmd);

    if ($runCmd->exit_code) {
        if ($self->param('fixed_aln')) {
            die "Problem running r2r: " . $runCmd->out . "\n";
        } else {
            $self->fix_aln_file($runCmd->out);
            $self->run_r2r_and_check($opts, $infile, $outfile, $extra_params);
        }
    }
    if (! -e $outfile) {
        die "Problem running r2r: $outfile doesn't exist\n";
    }
    return;
}

1;
