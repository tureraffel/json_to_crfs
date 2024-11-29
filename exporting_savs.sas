/*This script works with custom formatted tables genereted in script import_json_eval_...
a lot of statistic softwares don't work with special missings, so this removes special missings based on table t_missings
exports as .sav files where label/custom formating gets retained*/

%let sav_folder = C:\Users\raffelt\jsons_with_sas\savs; /*directory where .sav files are deposited, no quotation marks.*/

libname e "C:\Users\raffelt\jsons_with_sas\eval_format";
options fmtsearch = (e.formats);
run;

proc catalog cat=e.formats;
	copy out=work.formats;
quit;

data t_missings;
set e.t_missings;
run;

/*replace special missings with big outlier values*/
%macro unspecial_missings(table);

	data &table;
	    if _n_ = 1 then do;
	        /* Create the hash object for fast lookup */
	        declare hash h(dataset: 't_missings'); /* Link to the missings dataset */
	        
	        /* Define key and data for the hash object */
	        h.defineKey('special_missing'); /* Key variable */
	        h.defineData('value');           /* Data variable */
	        
	        h.defineDone(); /* Finalize the hash object definition */
			call missing(special_missing, value);
	    end;

	    set &table; /* Read data from the original dataset */
	    array vars _numeric_; /* Array to loop through all variables in the dataset */

	    /* Loop through all variables in the dataset */
	    do i = 1 to dim(vars);
	        /* Lookup if the current variable value matches any special_missing */
	        if h.find(key: vars[i]) = 0 then do; /* If key is found */
	            vars[i] = value; /* Replace the variable's value with the corresponding 'value' */
	        end;
	    end;

	    drop i special_missing value; /* Drop the loop index variable */
	run;

%mend;

/*takes a table with "normal" missing values and replaces them with special missings*/
%macro special_missings(table);

	data &table;
	    if _N_ = 1 then do;
	        /* Step 1: Create the hash object */
	        declare hash h(dataset: 't_missings'); /* Reference the lookup table */

	        /* Step 2: Swap key and data definitions */
	        rc = h.defineKey('value');           /* Use 'value' as the key */
	        rc = h.defineData('special_missing'); /* Use 'special_missing' as the data */
	        rc = h.defineDone();                 /* Finalize the hash object */

	        /* Step 3: Initialize the variables used by the hash object */
	        call missing(value, special_missing);
	    end;

	    /* Step 4: Read the main dataset */
	    set &table;
	    array vars _numeric_; /* Array to process all variables */

	    /* Step 5: Replace matching values */
	    do i = 1 to dim(vars);
	        /* Check if the current value exists in the hash table */
	        rc = h.find(key: vars[i]);
	        if rc = 0 then vars[i] = special_missing; /* If found, replace with the special missing */
	    end;

	    drop i rc special_missing value; /* Clean up unnecessary variables */
	run;

%mend;

/*takes a table with special missings. makes table %unspecial_missings, and then exports it as sav. path doesn't include filename. file saved as tablename_labeled
don't enter path in ""*/
%macro export_sav(table=, filepath=, lib=);

	/*create changing copy of table*/
	data &table.2;
		set &lib..&table;
	run;

	%unspecial_missings(&table.2);

	%let outfile = &filepath.\&table..sav;
	proc export data = &table.2
			outfile = "&outfile."
			dbms = sav
			replace;
			label;
	run;

	/*delete table*/
	proc sql;
		drop table &table.2;
	quit;

%mend;

/*imports a sav. makes missings special (%special_missings). creates a table in library, requires filepath without filename. assumes that all tables are in same directory, filenames = tablenames*/
/*currently doesn't format special missings correctly*/
%macro import_sav(table=, filepath=, lib=);
	%let inpath = &filepath.\&table..sav;
	proc import datafile = "&inpath."
				out=&lib..&table
				dbms=sav
				replace;
	run;

	%special_missings(&lib..&table);
%mend;
*%import_sav(table=acq, filepath=C:\Users\raffelt\jsons_with_sas\savs, lib=work);


/*this macro applies another macro to every table in a library*/
/*primary purpose is automating export as savs/importing savs*/
%macro apply_macro_to_lib(lib=, macro=, filepath=);
    /* Ensure the library name is valid */
    %if %sysfunc(libref(&lib)) ne 0 %then %do;
        %put ERROR: Library &lib does not exist.;
        %return;
    %end;

    /* Use PROC SQL to retrieve table names from the library */
    proc sql noprint;
        select memname 
        into :table_list separated by ' ' 
        from dictionary.tables
        where libname = upcase("&lib");
    quit;

    /* Check if there are tables in the library */
    %if &sqlobs = 0 %then %do;
        %put WARNING: No tables found in library &lib.;
        %return;
    %end;

    %let num_tables = %sysfunc(countw(&table_list));

    /* Loop through each table and call the passed macro */
    %do i = 1 %to &num_tables;
        %let table = %scan(&table_list, &i);

        /* Optional filepath inclusion in the macro call */
        %if %length(&filepath) > 0 %then %do;
            %put Applying macro &macro to table &lib..&table with filepath=&filepath;
            %&macro(lib=&lib, table=&table, filepath=&filepath);
        %end;
        %else %do;
            %put Applying macro &macro to table &lib..&table without filepath;
            %&macro(lib=&lib, table=&table);
        %end;
    %end;
%mend;

%apply_macro_to_lib(lib=e, macro=export_sav, filepath=&sav_folder);
