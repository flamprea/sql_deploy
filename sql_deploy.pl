#!perl

# Version: 1.0
# Date: December 2007
# Author: Francis J. Lamprea
# BladeLogic, Inc.

# Description:
# Deploy SQL Scripts as part of application deployment

use DBI;
use Getopt::Std;

### START MAIN ###

#--------------------------------------
# Get Options from Command Line
getopts("c:d:u:p:q:s:");
# -c = utility & configuration db server
# -d = utility & configuration db name
# -u = utility & configuration db user
# -p = utility & configuration db password
# -q = utility & configuration db query
# -s = sql script share

#--------------------------------------
# Test the options to make sure we have everything we need to proceed
if ((!($opt_c)) || 
    (!($opt_d)) || 
    (!($opt_u)) || 
    (!($opt_p)) || 
    (!($opt_q)) || 
    (!($opt_s)) ) {

    # Exit to the subroutine if something is missing
    &errorexit;
}
#--------------------------------------
# Define Variables from ARGV
my $dbserver = $opt_c;
my $db = $opt_d;
my $dbuid = $opt_u;
my $dbpwd = $opt_p;
my $dbquery = $opt_q;
my $scriptshare = $opt_s;
# Define internal variables
my @sortedfiles = '';
my @targetServer = '';
my @targetDb = '';
my @targetUid = '';
my @targetPwd = '';
my $loopCounter = 0;
my $foundError = 0;

&time && print "[$year-$mon-$mday $hour:$min:$sec] Initializing...\n";

# Retrive and order the list of SQL scripts
&fileList;

# Retrieve the list of target DB servers
&targetList;

# Run the list of scripts on each target
$loopCounter = 0;
foreach (@targetServer) {
      
      &time && print "[$year-$mon-$mday $hour:$min:$sec] Connecting to $dbserver:$db as $dbuid\n";
      my $DSN = "driver={SQL Server};Server=$targetServer[$loopCounter];database=$targetDb[$loopCounter];uid=$targetUid[$loopCounter];pwd=$targetPwd[$loopCounter];" or warn "Cannot create DSN Object\n";
      my $dbh  = DBI->connect("dbi:ODBC:$DSN") or warn "$DBI::errstr\n";
      
      foreach $file (@sortedfiles) {
            
            # Define the SQL Statement
            &time && print "[$year-$mon-$mday $hour:$min:$sec] Reading $file\n";
            open(FILE, "$file") or warn "Unable to open $file: $!\n";
            # read file into an array
            @data = <FILE>;
            # close file
            close(FILE);
            
            # Flatten the array
            $myStmt = join(" ",@data);
      
            # Prepare and Execute the Query
            &time && print "[$year-$mon-$mday $hour:$min:$sec] Passing statement to $dbserver:$db\n";
            $sth = $dbh->prepare("$myStmt") or warn "Could not prepare statement: "  . $dbh->errstr . "\n";
            $sth->execute()or $foundError = 1 && print "Could not execute statement: "  . $sth->errstr . "\n";
            $sth->finish;
                
      }

      $loopCounter++;
        
      # Close and Disconnect SQL
      &time && print "[$year-$mon-$mday $hour:$min:$sec] Closing DB Connection\n";
      $dbh->disconnect;
}

# tear down
&time && print "[$year-$mon-$mday $hour:$min:$sec] Process Complete\n";

if ($foundError == 1) {
      print "An error was detected\n";
      exit 1;
}

exit 0;
### END OF MAIN ###

# Exit the application with instructions that the command
# line parameters are not correct
sub errorexit {
   print "\n
      -c = utility & configuration db server
      -d = utility & configuration db name
      -u = utility & configuration db user
      -p = utility & configuration db password
      -q = utility & configuration db query
      -s = sql script share\n";
   exit 1;
}

# Set Date Parameters for use within script
sub time {
   ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)=localtime();
           $year=$year+1900;                       #Calculate the correct Year
           $mon++;                                 #Shift Month +1
           $mon=sprintf("%02d", $mon % 100);       #Round month to 2 digits;
           $mday=sprintf("%02d", $mday % 100);     #Round date to 2 digits;
           $hour=sprintf("%02d", $hour % 100);     #Round hour to 2 digits;
           $min=sprintf("%02d", $min % 100);       #Round minute to 2 digits;
           $sec=sprintf("%02d", $sec % 100);       #Round second to 2 digits;
}

# Connect to the share and create an ordered list of files
sub fileList {
      &time && print "[$year-$mon-$mday $hour:$min:$sec] Retrieving file list...\n";
      @tempfiles = <$scriptshare\\*.sql>;

      # Eliminate non-files from the list
      foreach (@tempfiles) {
            	next unless -f;
            	push(@files, "$_");
      }

# Sort alphabetically since script execution order is important!!
      @sortedfiles = sort(@files);
}

# Create the SQL connection object to the maintenance database
sub targetList {
      &time && print "[$year-$mon-$mday $hour:$min:$sec] Connecting to $dbserver:$db as $dbuid\n";
      my $DSN = "driver={SQL Server};Server=$dbserver;database=$db;uid=$dbuid;pwd=$dbpwd;" or die "Cannot create DSN Object\n";
      my $dbh  = DBI->connect("dbi:ODBC:$DSN") or die "$DBI::errstr\n";
            
          # Define the SQL Statement
          $myStmt =	"$dbquery";
            
          # Prepare and Execute the Query
          $sth = $dbh->prepare("$myStmt") or die "Could not prepare statement: "  . $dbh->errstr . "\n";
          $sth->execute()or die "Could not execute statement: "  . $sth->errstr . "\n";
            
               
               # Iterate through the query and write it out to an array
               while (@row = $sth->fetchrow_array) { 
                   
                   ($targetServer[$loopCounter], $targetDb[$loopCounter], $targetUid[$loopCounter], $targetPwd[$loopCounter]) = @row;
                   
                   $loopCounter++;
                   
                   } 
            
            if ($sth->rows == 0) {
                  &time && print "[$year-$mon-$mday $hour:$min:$sec] No rows matched\n";
                  exit 1;
            }
      
            
            # Close and Disconnect SQL
            &time && print "[$year-$mon-$mday $hour:$min:$sec] Closing DB Connection\n";
            $sth->finish;
            $dbh->disconnect;
}
