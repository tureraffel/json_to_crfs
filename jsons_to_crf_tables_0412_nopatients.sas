/* Aktivieren der JSON Engine und Optionen setzen */
options validvarname=any;
options noquotelenmax;

/* Definieren der JSON-Libname */
libname jsonlib json "C:\Users\raffelt\jsons_with_sas\patient_data_export1411_2.json";

/*this lib contains exclusively my output tables, where each table corresponds to one test*/
libname out "C:\Users\raffelt\jsons_with_sas\out2";
run;

/*this lib contains pretty, formatted, evaluated tests*/
libname e "C:\Users\raffelt\jsons_with_sas\e2";
run;
options fmtsearch=(e.formats); /*formate werden hier abgelegt*/


/* Macro zum Importieren aller Tabellen */
%macro import_all_tables;
    /* Alle Tabellen in der JSON-Libname auflisten */
    proc sql noprint;
        select memname into :tables separated by ' '
        from dictionary.tables
        where libname = 'JSONLIB';
    quit;

    /* Jede Tabelle in die Work-Bibliothek kopieren */
    %let i = 1;
    %do %while (%scan(&tables, &i) ne );
        %let table = %scan(&tables, &i);
        data work.&table;
            set jsonlib.&table;
        run;
        
        /* Ausgabe der ersten paar Zeilen jeder Tabelle
        proc print data=work.&table (obs=5);
            title "Erste 5 Zeilen von &table";
        run; */

        %let i = %eval(&i + 1);
    %end;
%mend;

/* Macro ausführen */
%import_all_tables;

/*create a table for missing values to be stored in*/
proc sql;
create table t_missings 
	(value num,
	special_missing num,
	format_comment char(50));

	insert into t_missings
	values(99999, .Z, "TEST NICHT AUSGEFÜLLT")
	values(99998, .Y, "FRAGE NOCH NICHT VERFÜGBAR")
	values(99997, .X, "KEINE ANGABE DURCH PATIENT")
	values(99973, .A, "UNKNOWN");
quit;

data old_crfs_items;
set crfs_items;
run;


/*change variable "value" to numeric*/
/*FEHLERQUELLE: VARIABLEN WERDEN MANUELL IN NUMERISCHE ÜBERSETZT*/
data crfs_items;
set crfs_items;
value = compress(value);

variable_name = compress(translate(translate(variable_name, "","-"),"",":")); /*get rid of "-" and ":"*/
if variable_name = "signature" and value ^= "" then value = "1";
else if variable_name = "signature" and value = "" then value = "0";/*ersetzt den faceroll der bei signatur entsteht durch 1 oder 0*/
if value = "" then value = "99999"; /*missing: test wurde nicht ausgefüllt*/
else if upcase(substr(value, 1, 6)) = upcase("sample") then value = "99998"; /*missing: Werte noch nicht verfügbar*/
else if value = "N/A" then value = "99997"; /*Missing: Patient machte keine Angabe*/
run;

data crfs_items;
set crfs_items;
num_value = input(value, 8.);
drop value;
rename num_value = value;
run;


proc sort out=crfs_items
	data= crfs_items;
	by value;
run;
proc sort out=t_missings
	data=t_missings;
	by value;
run;


/*change crfnames/ variablenames to replace "-" with "_". also removes ":" and spaces -> easy sorting later*/
data old_crfs;
set crfs;
run;
data crfs;
set crfs;
crf_name = compress(translate(crf_name, "_","-"), " :");
*if lengthn(crf_name) > 10 then crf_name = substr(crf_name, 1, 20); /*truncate tablename in a manner most brutish (an attempt at making formatname shorter)*/
run;

/*Create a table with only the names of each test*/
proc sort	data = crfs (keep=crf_name)
			out = unique_crfs nodupkey;
by _all_;
run;

/*get a table with all variable labels to look through later*/
proc sort	data = crfs_items (keep=variable_name field_label)
			out = var_labels nodupkey;
by _all_;
run;

/*getting a macro variable list from t.uniques excluding the dsvgo_questionnaire*/
proc sql noprint;
	select crf_name
	into :table_names separated by ' '
	from unique_crfs
	where upcase(crf_name) not like upcase('DSGVO%');
quit;

data old_items_codes;
set items_codes;
run;

/*make nvalue actually numeric*/
data items_codes;
set items_codes;
num_value = input(nvalue, 8.);
drop nvalue;
rename num_value = nvalue;
run;


/*takes a table with "normal" missing values and replaces them with special missings*/
%macro special_missings(table);

	data &table;
	    if _N_ = 1 then do;
	        /*Create the hash object*/
	        declare hash h(dataset: 't_missings');

	        /*Swap key and data definitions*/
	        rc = h.defineKey('value');         
	        rc = h.defineData('special_missing');
	        rc = h.defineDone();

	        /*Initialize the variables used by the hash object*/
	        call missing(value, special_missing);
	    end;

	    /*Read the main dataset */
	    set &table;
	    array vars _numeric_;

	    /*Replace matching values*/
	    do i = 1 to dim(vars);

	        rc = h.find(key: vars[i]);
	        if rc = 0 then vars[i] = special_missing;
	    end;

	    drop i rc special_missing value; /* Clean up unnecessary variables */
	run;

%mend;

/*joins given table on ordinal_crfs with eval_table -> removes all empty variables and returns the new table as "&table_name"*/
%macro add_evaluation(tab_name);
	proc sql;
			create table eval as
			select * from &tab_name join crfs_evaluation on &tab_name..ordinal_crfs = crfs_evaluation.ordinal_crfs;
	quit;

	ods output nlevels = work.missing_vars;
	/*make a table that shows me missing vars*/
	proc freq data=eval nlevels;
		tables _all_ / missing noprint;
	quit;
	ods output close;

	/*makro variable with empty vars*/
	proc sql noprint;
		select tableVar into :allmiss separated by ' '
		from missing_vars where NNonMissLevels = 0;
	quit;

	data &tab_name;
		set eval(drop= %sysfunc(compbl(&allmiss)));
	run;
%mend;


/*extract numeric parts of variable and order by that. no numeric part -> 0*/
%macro order_variables(table);

	proc sql;
		create table columns as select
		name from dictionary.columns where
		libname = "WORK" and memname = upcase("&table");
	quit; 

	data order_columns;
		set columns;
		pos = compress(name, "_", "A");
		if pos = "" then pos ="0";
		pos = input(pos, best.);
	run;

	proc sql noprint;
		select name into :ordered_vars separated by ' '
		from order_columns order by pos;
		quit;

	data &table;
		retain patient_id &ordered_vars;
		set &table;
	run;

%mend;

/*apply labels to variable_names*/
%macro add_labels_to_vars(tab_name);
	%let sanitized_name = %sysfunc(compress(&tab_name, -)); /*get rid of hyphens*/

	/*creates a string variable_name = 'Actual Question asked in the CRF'*/
	proc sql noprint;
	    select name|| " = " || quote(trim(field_label))
	    into :label_statements separated by ' '
	    from dictionary.columns as cols
	         left join var_labels as lbl
	         on upcase(cols.name) = upcase(lbl.variable_name)
	    where upcase(cols.memname) = upcase("&tab_name") /* Dataset name */
	      and upcase(cols.libname) = 'WORK'; /* Library, change if needed */
	quit;

	/*apply labels by using the string from before*/
	data &tab_name (drop=_NAME_);
		set &tab_name;
		label &label_statements
			  patient_id = "Patienten ID";
	run;
%mend;


/*generate a format for the given variable of the given table*/
%macro format_col(column, table);

	proc sql;
		create table x as 
		select crfs_items.ordinal_items, crfs_items.variable_name, items_codes.nvalue, items_codes.cvalue from crfs_items
		join items_codes on crfs_items.ordinal_items = items_codes.ordinal_items
		where upcase(variable_name) = upcase("&column"); /*exact comparison with variable_name*/
	quit;

	/*get rid of duplicates*/
	proc sort	data=x (keep= nvalue cvalue)
				out=y
				nodupkey;
				by _all_;
	run;
	/*change form of table to make next function usable*/
	data form_tab;
		set y;
		retain type 'N';
		fmtname = cats('FMT_', symget('table'), '_', symget('column'), '_','f'); /*formats cant end with number*/
		start = nvalue;
		label = cvalue;
		keep fmtname type start label;
	run;

	data form_tab;
	set form_tab t_missings(keep=special_missing format_comment rename=(special_missing=start format_comment=label));
		fmtname = cats('FMT_', symget('table'), '_', symget('column'), '_','f');
		type = 'N';
	run;

	data form_tab;
	set form_tab t_missings(keep=value format_comment rename=(value=start format_comment=label));
		fmtname = cats('FMT_', symget('table'), '_', symget('column'), '_','f');
		type = 'N';
	run;

	/*turn table into format*/
	proc format	cntlin = form_tab;
	run;

%mend;


/*create a format for every column in a table -> applied later in macro %apply_formats.*/
%macro format_table(table_name);

	/*list of columns*/
	proc sql noprint;
		select translate(name, "", "-") /*hyphen to nothing*/ 
		into :cols separated by ' '
		from dictionary.columns
		where libname = 'WORK' /*!!!!*/
		and memname = UPCASE("&table_name")
		and UPCASE(name) not in ("PATIENT_ID", "ORDINAL_CRFS"); /*those values do not get formats*/
	quit;

	%let n_cols = %sysfunc(countw(&cols));

	%do j = 1 %to &n_cols;
		%let col_name = %scan(&cols, &j);

		%format_col(&col_name, &table_name);

	%end;

%mend;


%macro apply_formats(libname, tablename);
    proc sql noprint;
        /* Generate variable names and corresponding formats */
        select name,
               cats('Fmt_', "&tablename", '_', name, '_f') as format
        into :colnames separated by ' ',
             :formats separated by ' '
        from dictionary.columns
        where libname=upcase("&libname") 
              and memname=upcase("&tablename")
              and upcase(name) not in ('PATIENT_ID', 'ORDINAL_CRFS'); /* Exclude columns */
    quit;

    /* Apply the formats */
    data &libname..&tablename;
        set &libname..&tablename;
        %do j = 1 %to %sysfunc(countw(&colnames));
            %let colname = %scan(&colnames, &j);
            %let fmt = %scan(&formats, &j);

            format &colname &fmt..; /*$ For character variables -> vars are numeric though*/
        %end;
    run;
%mend;

/*combine previous macros. grab table from library "out" and save new table in library "e"*/
%macro pretty_table(tab_name);

	data &tab_name;
		set	out.&tab_name;
	run;
	
	%put Formatting table &tab_name;
	%format_table(&tab_name); /*-> create formats*/

	%put Applying formats to &tab_name;
	%apply_formats(work, &tab_name); /* -> &tab_name*/

	%put Adding labels to &tab_name;
	%add_labels_to_vars(&tab_name); /*->&tab_name*/

	%put Ordering variables in &tab_name;
	%order_variables(&tab_name); /*-> &tab_name*/

	%put Adding Evaluations to &tab_name;
	%add_evaluation(&tab_name); /*-> &tab_name*/

	%put Making Missings special in &tab_name;
	%special_missings(&tab_name); /*-> &tab_name*/
	
	%put Transferring &tab_name into library e;
	data e.&tab_name (drop=ordinal_crfs ordinal_evaluation);
		set &tab_name;
	run;

	proc datasets library=work nolist;
		delete &tab_name;
	quit;

%mend;

/*IMPORTANT - REPLACES HYPHENS WITH UNDERSCORES IN TEST NAMES WHEN CREATING A NEW TABLE:
EXAMPLE: bfi-10 becomes bfi_10*/
%macro create_tables;

	/*only allows log outputs for warnings, %put statements*/
	options nonotes;

    /* Count the number of table names */
    %let n_tables = %sysfunc(countw(&table_names, %str( )));

    /* Loop through each table name */
    %do i = 1 %to &n_tables;

        /* Get the table name for this iteration */
        %let table_name = %scan(&table_names, &i, %str( ));

        /* Truncate table name if longer than 10 characters*/
/*
		%if %sysfunc(lengthn(&table_name)) > 10 %then %do;
            %let table_name = %substr(&table_name, 1, 10);
        %end;
*/		
		%let sanitized_name = %sysfunc(compress(&table_name, -)); /*get rid of hyphens*/

		%put This is loop &i/&n_tables. Doing something to &table_name;

        /* Delete tables if they already exist */
        proc datasets library=work nolist;
            delete t_all t_pat t_items t_wide ordered missings eval labeled missing_vars t_cleaned;
        quit;

		proc sql;
			CREATE TABLE t_all as
			SELECT * FROM crfs
			WHERE UPCASE(crf_name) LIKE UPCASE("%trim(&table_name)%");

			CREATE TABLE t_pat as
			SELECT root.patient_id, * FROM t_all
			JOIN root ON root.ordinal_root = t_all.ordinal_root;

			CREATE TABLE t_items as
			SELECT * FROM t_pat
			JOIN crfs_items on t_pat.ordinal_crfs = crfs_items.ordinal_crfs
			order by patient_id;
		quit;

        /* Transpose data */
        proc transpose data=t_items(keep=patient_id variable_name value ordinal_crfs)
                       out=t_wide;
            id variable_name;
            var value;
            by patient_id ordinal_crfs;
        run;

		/*add col "completed". if 0 add missing 99999*/
		proc sql;
			create table thingy as 
			select t_wide.*, crfs.completed from t_wide join crfs on t_wide.ordinal_crfs = crfs.ordinal_crfs;
		quit;

		data thingy;
			set thingy;
			if completed = 0 then do;

				array vars {*} _numeric_;
				do i=1 to dim(vars);
					if missing(vars[i]) then vars[i] = 99999; /*missing value for "Test nicht ausgefüllt"*/
				end;
			end;
			drop i;
		run;

        /* Copy the transposed data to the 'out' library with the final name */
        data out.&sanitized_name(drop=_NAME_ completed);
            set thingy;
        run;

		/*make format nice*/
		%pretty_table(&table_name);
		
		
    %end;

	/*export formats into lib e*/
	proc catalog cat=work.formats;
		copy out=e.formats;
	quit;

	options fmtsearch=(e.formats);
	
	options notes;

	/*export t_missings aswell. key for formats maybe*/
	data e.t_missings;
	set t_missings;
	run;

%mend;

%create_tables;
