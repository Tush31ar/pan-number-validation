
-- function to check the adjacent character --VGLOD3180G
CREATE OR REPLACE FUNCTION fn_check_adjacent_character(p_str TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  FOR i IN 1 .. length(p_str) - 1   -- ✅ stop at second-to-last character
  LOOP
    IF substring(p_str, i, 1) = substring(p_str, i + 1, 1) THEN
      RETURN TRUE;
    END IF;
  END LOOP;

  RETURN FALSE;
END;
$$;	

-- function to check the sequential character
CREATE OR REPLACE FUNCTION fn_check_sequential_character(p_str TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  FOR i IN 1 .. length(p_str) - 1   -- ✅ stop at second-to-last character
  LOOP
    IF ascii(substring(p_str, i+1, 1)) - ascii(substring(p_str, i , 1)) <> 1 THEN
      RETURN FALSE; -- check if character is not in sequence
    END IF;
  END LOOP;

  RETURN TRUE; -- check if character is in sequence
END;
$$;	

-- categorization of Pan Numbers as valid or invalid
create or replace view vw_valid_invalid_pan
as
WITH cte_cleaned_pan AS (
    SELECT DISTINCT upper(trim(pan_number)) AS pan_number
    FROM pan_numbers_dataset
    WHERE pan_number IS NOT NULL
      AND trim(pan_number) <> ''
),
cte_valid_pan AS (
    SELECT *
    FROM cte_cleaned_pan
    WHERE fn_check_adjacent_character(pan_number) = FALSE
      AND fn_check_sequential_character(substring(pan_number, 1, 5)) = FALSE
      AND pan_number ~ '^[A-Z]{5}[1-9]{4}[A-Z]$'
)
SELECT
    cld.pan_number,
    CASE
        WHEN vld.pan_number IS NOT NULL THEN 'Valid PAN'   -- ✅ single quotes
        ELSE 'Invalid PAN'                                  -- ✅ single quotes
    END AS pan_status                                       -- ✅ END + alias
FROM cte_cleaned_pan cld
LEFT JOIN cte_valid_pan vld ON cld.pan_number = vld.pan_number;

-- Summary Report
with cte as
(select
	(select count(*) from pan_numbers_dataset) as Total_records_processed
	,	count(*) filter (where pan_status = 'Valid PAN') as Total_valid_PANs
	,	count(*) filter (where pan_status = 'Invalid PAN') as Total_invalid_PANs
		from vw_valid_invalid_pan
)
select Total_records_processed
, 		Total_valid_PANs
,		Total_invalid_PANs
,		(Total_records_processed - (Total_valid_PANs + Total_invalid_PANs)) 
		as Total_missing_PANs
from cte
