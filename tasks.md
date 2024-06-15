

### Tasks

1. Core functions: refine default schema generation
	- Support schema generation based on provided schema path
	- generated schema has id value in the JSON  
	- construct JSON based on the db schema 
	- error handling
	- handle collection exclusions and inclusions
    
2. Core functions: Structure for start export - for one collection, synchronously 
	- start function
	- drop/truncate existing tables and create/recreate table
	- Data structure for quick source to destination field lookup
	- read mongo data using cursor and iterate
	- generate insert/upsert SQL
		
