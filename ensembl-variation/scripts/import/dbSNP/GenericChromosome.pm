use strict;

=head1 LICENSE

  Copyright (c) 1999-2013 The European Bioinformatics Institute and
  Genome Research Limited.  All rights reserved.

  This software is distributed under a modified Apache license.
  For license details, please see

    http://www.ensembl.org/info/about/legal/code_licence.html

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk.org>.

=cut

use warnings;
#object that contains the specific methods to dump data when there are chromosome coordinates from dbSNP (not contigs, as usual). 
#So far, this is the case for rat and chicken
package dbSNP::GenericChromosome;

use dbSNP::GenericContig;
use vars qw(@ISA);
use ImportUtils qw(debug load dumpSQL create_and_load);
use Progress;

@ISA = ('dbSNP::GenericContig');

sub variation_feature{
    my $self = shift;

     debug(localtime() . "\tDumping seq_region data");

     #only take toplevel coordinates
     dumpSQL($self->{'dbCore'}->db_handle, qq{SELECT sr.seq_region_id, 
  				      if (sr.name like "E%", CONCAT("LG",sr.name),sr.name) ##add LG for chicken
  				      FROM   seq_region_attrib sra, attrib_type at, seq_region sr
  				      WHERE sra.attrib_type_id=at.attrib_type_id 
 	                              AND at.code="toplevel" 
                                       AND sr.seq_region_id = sra.seq_region_id 
 				    });


     debug(localtime() . "\tLoading seq_region data");
     load($self->{'dbVar'}, "seq_region", "seq_region_id", "name");
     print Progress::location();
     my $version_number = substr($self->{'dbSNP_version'},1);
     debug(localtime() . "\tDumping SNPLoc data for dbSNP version $version_number " );
    
     my ($tablename1,$tablename2,$row);

    if(  $version_number  < 137){ ## table rename for dbSNP - keeping this temporarily for backwards comparibility


     print "assembly_version is ",$self->{'assembly_version'},"\n";
     my ($assembly_version) =  $self->{'assembly_version'} =~ /^[a-zA-Z]+\_?(\d+)\.*.*$/;
     $assembly_version=$1 if $self->{'assembly_version'} =~ /RGSC\d\.(\d+)/;

     my $stmt = qq{
                   SELECT 
                     name 
                   FROM 
                     $self->{'snp_dbname'}..sysobjects 
                   WHERE 
                     name LIKE '$self->{'dbSNP_version'}\_SNPContigLoc\_%'
		    ORDER BY
			name DESC
                  };
     my $sth = $self->{'dbSNP'}->prepare($stmt);
     $sth->execute();

    my $genome_build;
    my @genome_builds;
     while($row = $sth->fetchrow_arrayref()) {
	($genome_build) = $row->[0] =~ m/SNPContigLoc\_(.+)$/;
	push(@genome_builds,$genome_build) if ($genome_build);
     }

    if (scalar(@genome_builds) != 1) {
	if (!scalar(@genome_builds)) {
	    die("Could not find the " . $self->{'dbSNP_version'} . "_SNPContigLoc_NNN table!");
	}
	warn("SNPContigLoc tables for multiple builds found, guessing that the one to use is " . $genome_builds[0]);
    }
    $genome_build = shift(@genome_builds);
    $tablename1 = $self->{'dbSNP_version'} . "_SNPContigLoc_" . $genome_build;
    
     $stmt = qq{
                SELECT 
                  name 
                FROM 
                  $self->{'snp_dbname'}..sysobjects 
                WHERE 
                  name LIKE '$self->{'dbSNP_version'}\_ContigInfo\_$assembly_version\_%'
               };
     my $sth1 = $self->{'dbSNP'}->prepare($stmt);
     $sth1->execute();

     while($row = $sth1->fetchrow_arrayref()) {
       $tablename2 = $row->[0];
     }
     
    $tablename2 = $self->{'dbSNP_version'} . "_ContigInfo_" . $genome_build;
    
     print "SNPContigLoc table is $tablename1 and ContigInfo table is $tablename2\n";
   

    }

     else{
    $tablename1 = $self->{'dbSNP_version'} . "_SNPContigLoc" ;
    $tablename2 = $self->{'dbSNP_version'} . "_ContigInfo";
     }
my $stmt;
    #�The group term (the name of the reference assembly in the dbSNP b[version]_SNPContigInfo_[assembly]_[assembly version] table) is either specified via the config file or, if not, attempted to automatically determine from the data
    my $group_term = $self->{'group_term'};
    my $group_label = $self->{'group_label'};
    if (defined($group_term) && defined($group_label)) {
	warn "Using group_term:$group_term and group_label:$group_label to extract mappings \n";
    }
    else{        
        #�If no group term was specified, use the one with the most entries in the dbSNP table. This may be wrong though so warn about it.
        $stmt = qq{
            SELECT
                ctg.group_term,
                ctg.group_label,
                COUNT(*) AS N
            FROM
                $tablename1 loc JOIN 
		        $tablename2 ctg ON (
		            ctg.ctg_id = loc.ctg_id
		        )
		    GROUP BY
 		        ctg.group_term,
		        ctg.group_label
            ORDER BY
                N DESC
        };
        my $result = $self->{'dbSNP'}->db_handle->selectall_arrayref($stmt);
        $group_term = $result->[0][0];
        $group_label = $result->[0][1];
        print Progress::location();
        
        #�Warn about the group_term we settled for
        debug(
            qq{
                There was no 'group_term' specified in the config file. 
                What this means is that dbSNP maps variations to multiple assemblies. These
                are indicated by the 'group_term' column in the $tablename2 table. We only import
                chromosome labels for the mappings to the reference assembly we have in Ensembl and
                for the other mappings we import the contig label. For example, in human dbSNP132, the
                group_term for GRCh37 is 'GRCh37'. You can specify this with the 'group_term' option in
                the configuration file.
                However, in order to save you the trouble, for now we'll just take the group_term with the
                most entries in the current dbSNP table and hope that it is the correct one. If it's not you'll
                have to truncate the variation_feature table and re-run the variation_feature subroutine.
                
                Based on this approach, we'll use the group term '$group_term' and group label '$group_label'.
            }
        );
    }
    
    # In the query below, the pre-131 syntax was ref-assembly. In 131 it is GRCh37 for human. What is it for other species??
    #my $group_term = 'ref_';
    #my ($release) = $self->{'dbSNP_version'} =~ m/^b?(\d+)$/;
    #$group_term = 'GRCh' if ($self->{'dbm'}->dbCore()->species =~ m/homo|human/i && $release > 130);
    
	#	     t2.group_term LIKE 'ref_%'
     $stmt = "SELECT ";
     if ($self->{'limit'}) {
       $stmt .= "TOP $self->{'limit'} ";
     }
    ### 2012/07 Mitochondria mappings extracted for human only until references stabilise for other species
    my $extract_mappings_for;
   # if($self->{'dbm'}->dbCore()->species =~ m/homo|human/i){
	$extract_mappings_for = qq['$group_term', 'non-nuclear'];
    #}
    #else{
	#$extract_mappings_for = qq['$group_term'];
    #}
     $stmt .= qq{
                   loc.snp_id AS sorting_id, 
                   ctg.contig_acc,
		   ctg.contig_gi,
                   loc.lc_ngbr+2,
		   loc.rc_ngbr,
		   ctg.contig_chr, 
		   CASE WHEN
		     loc.loc_type = 3
		   THEN
		     loc.phys_pos_from+2
		   ELSE
		     loc.phys_pos_from+1
		   END,
		   CASE WHEN
		     loc.loc_type = 3
		   THEN
		     loc.phys_pos_from+1
		   ELSE
		     loc.phys_pos_from+LEN(loc.allele)
		   END,
		   CASE WHEN
		     loc.orientation = 1
		   THEN
		     -1
		   ELSE
		     1
		   END,
                   loc.aln_quality
		 FROM 
		   $tablename1 loc JOIN 
		   $tablename2 ctg ON (
		     ctg.ctg_id = loc.ctg_id
		   )
      WHERE
        ctg.group_term in($extract_mappings_for) AND
        ctg.group_label LIKE '$group_label'
	        };
     if ($self->{'limit'}) {
       $stmt .= qq{    
		   ORDER BY
		     sorting_id ASC  
	          };
     }
 				 #AND t2.group_term like "ref_%"
     dumpSQL($self->{'dbSNP'},$stmt);
    
    
    debug(localtime() . "\tLoading SNPLoc data");
    ## seh - set indexed columns to not null
     create_and_load($self->{'dbVar'}, "tmp_contig_loc_chrom", "snp_id i* not_null", "ctg * not_null", "ctg_gi i", "ctg_start i not_null", "ctg_end i", "chr *", "start i", "end i", "strand i", "aln_quality d");
  print Progress::location();

    #�As a correction for the human haplotypes that dbSNP actually reported on the chromosome 6 (and 4 & 17), cross-check the ctg_gi against the pontus_dbsnp_import_external_data.refseq_to_ensembl table and replace the chr if necessary
    if ($self->{'dbm'}->dbCore()->species() =~ m/homo_sapiens|human/i) {
	
	#�Add an index on contig_gi to the tmp_contig_loc_chrom table
	$stmt = qq{
	    CREATE INDEX
		ctg_gi_idx
	    ON
		tmp_contig_loc_chrom (
		    ctg_gi ASC
		)
	};
	$self->{'dbVar'}->do($stmt);
	print Progress::location();
	
	# Replace the chr name with the haplotype name if necessary
	$stmt = qq{
	    UPDATE
		tmp_contig_loc_chrom loc,
		pontus_dbsnp132_human_external_data.refseq_to_ensembl hap
	    SET
		loc.chr = hap.ensembl_id
	    WHERE
		loc.ctg_gi = hap.gi
	};
	$self->{'dbVar'}->do($stmt);
	print Progress::location();
	
	# Drop the contig_gi index again since we don't need it anymore
	$stmt = qq{
	    DROP INDEX
		ctg_gi_idx
	    ON
		tmp_contig_loc_chrom
	};
	$self->{'dbVar'}->do($stmt);
	print Progress::location();
    }
    
    debug(localtime() . "\tCreating genotyped variations");
    #creating the temporary table with the genotyped variations

    my $gtype_ref = $self->{'dbVar'}->db_handle->selectall_arrayref(qq{SELECT COUNT(*) FROM  tmp_individual_genotype_single_bp});
    my $gtype_row = $gtype_ref->[0][0] if $gtype_ref;
    if ($gtype_row) {
	$self->{'dbVar'}->do(qq{CREATE TABLE tmp_genotyped_var SELECT DISTINCT variation_id FROM tmp_individual_genotype_single_bp});
	print Progress::location();
	$self->{'dbVar'}->do(qq{CREATE UNIQUE INDEX variation_idx ON tmp_genotyped_var (variation_id)});
	print Progress::location();
	$self->{'dbVar'}->do(qq{INSERT IGNORE INTO tmp_genotyped_var SELECT DISTINCT variation_id FROM individual_genotype_multiple_bp});
	print Progress::location();
    }
    debug(localtime() . "\tCreating tmp_variation_feature_chrom data  in GenericChromosome");
    #if tcl.end>1, this means we have coordinates for chromosome, we will use it
    dumpSQL($self->{'dbVar'},qq{SELECT v.variation_id, ts.seq_region_id, 
                                      tcl.start,tcl.end,
                                      tcl.strand, v.name, v.source_id, v.validation_status, tcl.aln_quality
				      FROM variation v, tmp_contig_loc_chrom tcl, seq_region ts
				      WHERE v.snp_id = tcl.snp_id
				      AND tcl.start>2 #to get rid of lots of start=1
                                      AND tcl.chr = ts.name
    });

    create_and_load($self->{'dbVar'},'tmp_variation_feature_chrom',"variation_id i* not_null","seq_region_id i", "seq_region_start i", "seq_region_end i", "seq_region_strand", "variation_name", "source_id", "validation_status", "aln_quality d");
  print Progress::location();
    
    debug(localtime() . "\tCreating tmp_variation_feature_ctg data  in GenericChromosome");
    #if tcl.start = 1 or tcl.end=1, this means we don't have mappings on chromosome, we take ctg coordinates if it is in toplevel
    dumpSQL($self->{'dbVar'},qq{SELECT v.variation_id, ts.seq_region_id, 
                                      tcl.ctg_start,tcl.ctg_end,
                                      tcl.strand, v.name, v.source_id, v.validation_status, tcl.aln_quality
				      FROM variation v, tmp_contig_loc_chrom tcl, seq_region ts
				      WHERE v.snp_id = tcl.snp_id
				      AND (
					tcl.start = 1 OR
					tcl.end = 1 OR
					tcl.start IS NULL OR
					tcl.end IS NULL
				      )
                                      AND tcl.ctg = ts.name
   });

    create_and_load($self->{'dbVar'},'tmp_variation_feature_ctg',"variation_id i* not_null","seq_region_id i ", "seq_region_start i", "seq_region_end i", "seq_region_strand", "variation_name", "source_id", "validation_status", "aln_quality d");
  print Progress::location();

    debug(localtime() . "\tDumping data into variation_feature table in GenericChromosome");
    if ($gtype_row) {
      foreach my $table ("tmp_variation_feature_chrom","tmp_variation_feature_ctg") {

	$self->{'dbVar'}->do(qq{INSERT INTO variation_feature (variation_id, seq_region_id,seq_region_start, seq_region_end, seq_region_strand,variation_name, flags, source_id, validation_status, alignment_quality, somatic)
				  SELECT tvf.variation_id, tvf.seq_region_id, tvf.seq_region_start, tvf.seq_region_end, tvf.seq_region_strand,tvf.variation_name,IF(tgv.variation_id,'genotyped',NULL), tvf.source_id, tvf.validation_status, tvf.aln_quality,  v.somatic
				  FROM $table tvf LEFT JOIN tmp_genotyped_var tgv ON tvf.variation_id = tgv.variation_id
                                  LEFT JOIN variation v on tvf.variation_id = v.variation_id
				  });



  print Progress::location();
      }

      #last fill in flags with genotyped
      $self->{'dbVar'}->do(qq{UPDATE variation_feature vf, tmp_genotyped_var tgv
                              SET vf.flags = "genotyped"
                              WHERE vf.variation_id = tgv.variation_id
                              });

  print Progress::location();

    }
    else {

      debug(localtime() . "\tDumping data into variation_feature table only used if table tmp_genotyped_var is not ready");
      foreach my $table ("tmp_variation_feature_chrom","tmp_variation_feature_ctg") {
	$self->{'dbVar'}->do(qq{INSERT INTO variation_feature (variation_id, seq_region_id,seq_region_start, seq_region_end, seq_region_strand,variation_name, flags, source_id, validation_status, alignment_quality, somatic)
 				  SELECT tvf.variation_id, tvf.seq_region_id, tvf.seq_region_start, tvf.seq_region_end, tvf.seq_region_strand,tvf.variation_name,NULL, tvf.source_id, tvf.validation_status, tvf.aln_quality, v.somatic
 				  FROM $table tvf, variation v
                                  WHERE v.variation_id = tvf.variation_id
 				  });
  print Progress::location();
      }
    }


    #$self->{'dbVar'}->do("DROP TABLE tmp_contig_loc_chrom");
    #$self->{'dbVar'}->do("DROP TABLE tmp_genotyped_var");
    #$self->{'dbVar'}->do("DROP TABLE tmp_variation_feature_chrom");
    #$self->{'dbVar'}->do("DROP TABLE tmp_variation_feature_ctg");
    #for the chicken, delete 13,000 SNPs that cannot be mapped to EnsEMBL coordinate
    if ($self->{'dbm'}->dbCore()->species =~ /gga/i){
	$self->{'dbVar'}->do("DELETE FROM variation_feature WHERE seq_region_end = -1");
  print Progress::location();
    }
}

1;
