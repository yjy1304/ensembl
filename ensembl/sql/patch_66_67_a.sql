# patch_66_67_a.sql
#
# Title: Update schema version.
#
# Description:
#   Update schema_version in meta table to 67.

UPDATE meta SET meta_value='67' WHERE meta_key='schema_version';

# Patch identifier
INSERT INTO meta (species_id, meta_key, meta_value)
  VALUES (NULL, 'patch', 'patch_66_67_a.sql|schema_version');
