#!/usr/bin/perl


use strict;
use Cwd;
use Getopt::Long;
use File::Path;
use File::Copy;
use Data::Dumper;
use XML::Simple;
use POSIX qw(strftime);

######################################################################
# DEFINE GLOBAL VARS
######################################################################
my $script = 'ip_report.pl';
my $rev = '0.1';

my %opt;
my %rpt;
my %rpt_all;
my $rob;
my $dir = getcwd();
my $user = getlogin || getpwuid($<);
my $date = strftime "%m/%d/%Y", localtime;
my $opts = "@ARGV";
my $libtop = qw( /lsc/projects/IP/ip_generic/rrita/workarea/tools/ip_report_card/source/revisions/libtop.txt );
my $xml = qw( /lsc/projects/IP/ip_generic/rrita/workarea/tools/ip_report_card/source/revisions/workdir.xml );
my $_libtop = qw( _libtop.txt );
my $_workdir = qw( _workdir.xml );
my ($key_,$lib_,$top_,$lib_top);


Getopt::Long::config ("no_auto_abbrev","no_pass_through");
if (! GetOptions (
                  "dir=s"		=> \$opt{dir},
                  "libtop=s"		=> \$opt{libtop},
                  "xml=s"		=> \$opt{xml},
                  "make=s"		=> \$opt{mk},
                  "fmt=s"		=> \$opt{fmt},
                  "debug=s"		=> \$opt{d},
                  "o|out=s"		=> \$opt{o},
                  "h|help"		=> \&USAGE,
                  )) { ERROR('[ERROR 00A]Invalid parameter') }


######################################################################
# MAIN
######################################################################

TEST();
MAIN();
exit(0);

######################################################################
# SUB MAIN
######################################################################
# get libtop > get xml > xml2hash > foreach libtop > mine hash

sub MAIN {
	
	$libtop = $opt{libtop} if $opt{libtop};
	$xml = $opt{xml} if $opt{xml};
	if ($opt{mk} eq "libtop"){copy($libtop, $_libtop); print "[INFO] Created $_libtop ...\n"}
	if ($opt{mk} eq "xmlin"){copy($xml, $_workdir); print "[INFO] Created $_workdir ...\n"}	
	return if $opt{mk};	
	
	my $ltop_ = PARSE_LIBTOP($libtop);	#hashed libtop
	my %ltop = %{$ltop_};
		DUMPER(\%ltop) if ($opt{d} eq "1a");
	
	my $data = XMLin($xml, ForceArray => 1 );
	
	foreach my$key (sort keys %ltop){	#loop from lib/top combo
		next unless $key;
		$key_ = $key;
			DUMPER($key) if ($opt{d} eq "1b");
		if ($key eq "logic_design"){	#for logic_design folder
			my $top = $ltop{$key}; $top_ = $top;
			$lib_top = $top;
			SEARCH($data, $top);
		}
		else {	#for custom_design folder
			foreach my$lib (sort keys %{$ltop{$key}}){
				my $top = $ltop{$key}{$lib};
				($lib_, $top_) = ($lib, $top);
				$lib_top = "$lib/$top";
				SEARCH($data, $top);
			}
		}
	}
	DUMPER(\%rpt_all) if ($opt{d} eq "1c");
	WRITE_XML(\%rpt_all, []) unless ($opt{fmt} eq "ip");

	
return;
}

######################################################################
# GET ALL LIB/TOP

sub PARSE_LIBTOP {
	my $file = shift;
	my ($lib, $top);
	my %ltop;
	open(LIBTOP, "<$file");
		my @data = (<LIBTOP>);
	close(LIBTOP);
	
	foreach my$l (@data){
		if ($l =~ /^\s*#|^\s*$/){ next }	#get only the uncommented sections
		my ($type, $lt) = ($l =~ '(\S+)\s*:\s*(\S+)');
		
		if ($lt =~ '(\S+)/(\S+)'){ ($lib, $top) = ($1, $2)}
		else { $top = $lt }		#for logic_design
		
		if ($type eq 'logic_design'){ $ltop{$type} = $top }	#hashing of libtop
		else {$ltop{$type}{$lib} = $top}
	}

return \%ltop;
}


######################################################################
# LOOP TRHOUGH HASHES

sub HASH_WALKER {
    my ($hash, $key_list, $callback) = @_;
    while (my ($key, $value) = each %$hash) {
    	push (@$key_list, $key) unless ($key eq "dir");
        if ('HASH' eq ref $value) {		#determine the type of reference
            HASH_WALKER ($value, $key_list, $callback);	#loop back
			pop @$key_list unless ($key eq "dir");	#going back to the previous dir
        }
        else {	#callback function
            $callback->($key, $value, $key_list);
        }
    }
}


######################################################################
# SAVED THE KEYS

sub SAVE_DATA {
    my ($key, $value, $key_list) = @_;
    pop @$key_list;	#remove last element
	
	my $type = "@$key_list[0]";	#test for the type
	if ($type eq "custom_data"){$type = "custom_design"};
	return unless ($type eq $key_);
		DUMPER("@$key_list[0]: $lib_/$top_") if ($opt{d} eq "4a");
		#substitute $lib and $top
	my @paths = map { s/\$lib/$lib_/; s/\$top/$top_/; $_ } @$key_list;
    my $path = join('/', @paths);	#create directory
		DUMPER($path) if ($opt{d} eq "4b");
		#hashed by directory
	$rpt{$path}{category} = $value if ($key eq 'category');
	$rpt{$path}{item} = $value if ($key eq 'item');	
	$rpt{$path}{files} = $value if ($key eq 'files');
    printf "k = %-10s  v = %-20s  path = [%s]\n", $key, $value, $path if ($opt{d} eq "4c");
}


######################################################################
# SAVED THE KEYS

sub SEARCH {
	my ($data, $top) = @_;
	my %report;
	my $report_;
		DUMPER($top) if ($opt{d} eq "5a"); #issue with the top;

	HASH_WALKER($data, [], \&SAVE_DATA);
		DUMPER(\%rpt) if ($opt{d} eq "5b");

	foreach my$key (sort keys %rpt){
		next unless ($key =~ /^$key_/);
		my $path = "$dir/$key";
		my $category = $rpt{$key}{category};
		my $item = $rpt{$key}{item};
		my $files = $rpt{$key}{files};
			DUMPER("$top : $key : $key_") if ($opt{d} eq "5c");
		
		next unless ($category && $item && $files);	#sanity checker
		
		my ($s_,$d_,$o_,$c_) = ("NOT STARTED","N/A","N/A","N/A");
		if (($path =~ m/\*$/) || (-d $path)){
				DUMPER("YES : $top : $key") if ($opt{d} eq "5d");
			($s_,$d_,$o_,$c_) = CHECKER($path,$files,$top,$s_,$d_,$o_,$c_);		
		}
			DUMPER("NO : $top : $key") if ($opt{d} eq "5e");
		$report_ = UPDATE(\%report,$top,$category,$item,$s_,$d_,$o_,$c_);
		%report = %{$report_};
	}
	DUMPER(\%report) if ($opt{d} eq "5f");
	WRITE_XML(\%report, $top) unless ($opt{fmt} eq "group");
	
return;
}


######################################################################
# UPDATE STATUS

sub UPDATE {
	my ($report_,$top,$category,$item,$s_,$d_,$o_,$c_) = @_;
	my %report = %{$report_};
		#rehash for auto xml translation
		
	foreach my$item_ (split('\|', $item)){
		$report{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{a_status} = $s_;
		$report{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{b_date} = $d_;
		$report{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{c_owner} = $o_;
		$report{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{d_comment} = $c_;

		$rpt_all{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{a_status} = $s_;
		$rpt_all{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{b_date} = $d_;
		$rpt_all{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{c_owner} = $o_;
		$rpt_all{report}{IP}{$lib_top}{category}{$category}{item}{$item_}{d_comment} = $c_;
	}
	
return \%report;
}


######################################################################
# WRITE OUTPUT XML FROM HASHES

sub WRITE_XML {
	my ($report_, $top) = @_;

	my $xmlo = XMLout($report_, KeepRoot => 1);	#convert HASHES to XML file format
		DUMPER($xmlo) if ($opt{d} eq "7a");
	
	my $xlog = GET_NAME($top);	#print output XML file
	my $xhead = HEADER();
	open(XML, ">$xlog");
		print XML $xhead;
		print XML $xmlo;
	close(XML);
	
return;
}


######################################################################
# VERIFY EXISTING FILES

sub CHECKER {														#===============> TASK is here!!!
	my ($path,$files,$top,$s_,$d_,$o_,$c_) = @_;
	my @files_ = map { s/\$top/$top/; $_ } split('\s+', $files);
	my $f;
	
	# if ($path =~ m/\*$/){
		# for my$file (@files_){ DUMPER("$path/$file") if ($opt{d} eq "8a");
			# # my $status = `soscmd objstatus "$path/$file"`;							#use exec file
			# my $status = "";							#use exec file
			# if ($status =~ m/^5/){ $s_ = "PASS" }
			# else { $s_ = "HALF DONE" }
			# push@f, $file;
		# }
	# }
	
	# opendir(DIR, $path); DUMPER($path) if ($opt{d} eq "8b");
	# foreach my$file (readdir(DIR)){ DUMPER("\t$path : $file") if ($opt{d} eq "8b");
		foreach my$file (@files_){
			# if ($file =~ m/$_/){
				# if (-e "$path/$file"){							#===============> directly check for history!!!
					# my $status = `soscmd objstatus "$path/$file"`;
					my $hist = "$path/$file.hist";
					my $status = system("soscmd history $path/$file > $hist");
					if (-e $hist){
						my $hist_ = GET_HIST($hist);
						my %history = %{$hist_};
						foreach my$n (sort {$b <=> $a} keys %history){
							$d_ = $history{$n}{at};
							$o_ = $history{$n}{by};
							$c_ = $history{$n}{log};
							last;
						}
						DUMPER("$file : $d_,$o_,$c_");
					}
					else { $s_ = "NOT DONE"; last }
					unlink $hist;										#===============> 1 status for multiple deliverables!!!
					# if ($status =~ m/^5/){ $s_ = "PASS" }
					# else { $s_ = "HALF DONE" }
				# }
				# else { $s_ = "FAIL" }
				$f .= "$path/$file\n";
			# }
		}
	# }
	# closedir(DIR);
	# $c_ = "@f";
	
return ($s_,$d_,$o_,$c_);
}


######################################################################
# WRITE OUTPUT XML FROM HASHES

sub GET_HIST {
	my $hist = shift;
	my %history;

	return unless (-e $hist);
	open(IN, "<$hist"); my @data = (<IN>); close(IN);

	my ($check, $rev);
    foreach (@data){
		if(/^\s*Action:\s+Check\s+In/i){ $check=1; next}
		if($check){
			if(/^\s*Revision:\s+(\d+)/i){ $rev=$1 }
			elsif(/^\s*By:\s+(\S+)/i){ $history{$rev}{by} = $1}
			elsif(/^\s*At\s+time:\s+(\S+)\s+\S+.*/i){ $history{$rev}{at} = $1}
			elsif(/^\s*change_summary:\s+(\S+.*)/i){ $history{$rev}{log} = $1}
			elsif(/^\s*Log:\s+\S+.*/i){undef $check; undef $rev}
		}
		else{ next}
    }
    DUMPER(\%history) if ($opt{d} eq "9a");
	
return \%history;
}















#=====================================================================
#=====================================================================
# UTILITY MODULES
#=====================================================================
#=====================================================================

######################################################################
# ERROR

sub ERROR {
	my $error = shift;
	print STDOUT "%Error: $error, try \'$script --help\'\n\n";
	exit (1);
}

######################################################################
# ERROR

sub TEST {
	$dir = $opt{dir} if $opt{dir};
	ERROR("Input -dir should be FULL PATH") unless ($dir =~ m/^\/|^C:\//);
	ERROR('Input -make should be either "libtop" or "xmlin"') if (($opt{mk})&&($opt{mk} !~ m/^libtop$|^xmlin$/i));

	if (!$opt{fmt}){ $opt{fmt} = "group"}
	elsif ($opt{fmt} !~ /^group$|^ip$/){ $opt{fmt} = "group"}

}

######################################################################
# DUMPER

sub DUMPER { print Dumper @_; return }

######################################################################
# MANAGE NAMING

sub GET_NAME {
	my $top = shift;
	my $out = $opt{o};
	if (!$opt{o}){
		if ($opt{fmt} eq "group"){ $out = "ip_report.xml"}
		else { $out = "$top"."_report.xml"}
	}

return $out;
}

######################################################################
# PRINT HEADER

sub HEADER {
my $xhead = <<"EOF";
<?xml version="1.0" encoding="utf-8" ?>
<!--
	// IP Report Card Automation
	// Log file generated by $script revision $rev.
	// 
	// USER: $user
	// DATE: $date
	// COMMAND: $script $opts
-->
EOF

return $xhead;
}













######################################################################
######################################################################
######################################################################
######################################################################

# HELP

sub USAGE {

print <<EOH;
--------------------------------------------------------------------------------------------------------
DESCRIPTION
        $script - A tool that mines IP workarea for IP Report Card status update.

        Default output filename: "<ip>_report.xml"

USAGE
        $script [option]

OPTION
        Required:
        -dir [workarea path]		full path of your workarea(default: pwd)
        -libtop [libtop file]		library/top list file(default: -make libtop)
        -xml [xml file]				workdir schema in xml file format(default: -make xml)

        Optional:
		-fmt [group|ip]				generate single xml report for all IPs
		-make [libtop|xml]			generate the default/sample/embedded libtop or xml file
		-debug [code ID]			access internal variables with predefined code ID
		-o [file name]				desired output file name
        -h|help						display help message

EXAMPLES
		1. %> $script
				-use the default IP workarea xml schema and defined libtop file
		2. %> $script -fmt group
                -same as above but group all IPs into 1 xml file
		3. %> $script -dir /lsc/projects/IP/ip_umc40lp/rrita/workarea -fmt group 
                -same as above but will check data in the directory provided
		4. %> $script -xml workdir.xml -libtop libtop.txt
                -This generates report based on the input xml and libtop file. Use pwd for checking data
		5. %> $script -make xml
                -This creates a sample input xml file

SCOPE AND LIMITATIONS
        1. Supports any workarea by providing info into a highly configurable xml input file.

REVISION HISTORY:
		1. 05/04/15[rrita] -initial version

--------------------------------------------------------------------------------------------------------
EOH
exit(1);
}

__END__
