# Bioconductor data package for JASPAR

## The sqlite file
The sqlite file can be generated from the mysql dump. 
The conversion script can be downloaded from [github](https://raw.github.com/gist/1287049/mysql2sqlite.sh).

Usage:
```sh
./mysql2sqlite.sh -u root -p jaspar | sqlite3 JASPAR_2010.sqlite
```


## The sites sequences
use DNAStringSetList to store all the sequences. 
There are thousands of sets of sequences there, so the speed might not be too bad to fetch from DNAStringSetList.

