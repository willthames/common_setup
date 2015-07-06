use strict;
use warnings;
use 5.10.1;

use JSON;
use DBI;
use File::Slurp;
use Getopt::Long;
use Data::Dumper;
use Safe;
use Time::HiRes qw(gettimeofday);

main();

exit(0);


sub main {
	my $queries = from_json(read_file('data.json'));

	my $query = 0;
	my $configfile;

	GetOptions(
		"q=i" => \$query,
		"c=s" => \$configfile,
	);

	die "You didn't specify a query to run (use -q )" if $query == 0;
	die "Config file not found " unless (-e 'localconfig' || -e $configfile);

	my $dbconfig = read_localconfig($configfile);
	my $dbh = db_connect($dbconfig);

	my $q = $queries->{$query} or die "query $query does not exist";

	run_query($dbh, $q);
}

sub read_localconfig {
	my $config = shift;

	my $s = Safe->new;

	my $localconfig = $config // 'localconfig';

	$s->permit('dofile');
	$s->rdo($localconfig);

	my $safe_root = $s->root;
	my %safe_package;
	{ no strict 'refs'; %safe_package = %{$safe_root . "::"}; }

	my @read_symbols = grep { /^db_/ and !/^INC$/ and !/::/ } (keys %safe_package);

	my %args = map { $_, ${$s->varglob($_)} } @read_symbols;

	return \%args;
}

sub run_query {
	my $dbh = shift;
	my $query = shift;

	my ($sstart, $ustart) = gettimeofday();
	$dbh->selectall_arrayref($query->{query}, undef, @{$query->{args}});
	my ($sfinish, $ufinish) = gettimeofday();

	my $udiff = $ufinish - $ustart;
	if ($udiff < 0) { 
		$udiff += 1000000;
		$sfinish -= 1;
	}
	my $sdiff = $sfinish - $sstart;

	print "Sec: $sdiff   USec: $udiff\n";

}

sub db_connect {
	my $args = shift;

	my $user = $args->{db_user};
	my $pass = $args->{db_pass};
	my $host = $args->{db_host};
	my $port = $args->{db_port};
	my $driver = $args->{db_driver};
	my $database = $args->{db_name};

	if($port == 0) {
		$port = 3306 if lc($driver) eq 'mysql';
		$port = 5432 if lc($driver) eq 'pg';
	}

	my $dbh = DBI->connect("dbi:$driver:dbname=$database;host=$host;port=$port", $user, $pass) or die;

	return $dbh;
}

