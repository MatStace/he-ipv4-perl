#!/usr/bin/perl

use 5.10.1;
use warnings;
use strict;
use Switch;

use YAML::Tiny;
use LWP::Protocol::https;
use WWW::Mechanize;
use Logger::Syslog;

our $userID = "";
our $userPass = "";
our $tunnelID = "";

our $debug = 5;

our @listURL = ("http://ifconfig.me/ip",
	"http://whatismyip.org/",
	"http://v4.ipv6-test.com/api/myip.php",
	"http://automation.whatismyip.com/n09230945.asp");

our $tunnelName = "he-ipv6";

###############
#### MAIN #####
###############

logger_prefix("he-ipv4:");

my $curUser = getlogin();
if ($debug == 5) { say("curUser :" . $curUser) }
if ($curUser ne "root") {
	slog("the IPv4 update script must be executed by root, not " . $curUser . ". exiting", 1);
	exit 1;
}
undef $curUser;

our $configFile = "/var/cache/he-ipv4.yml";
our $regexIP='^((?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))(?![\\d])';

unless (-e $configFile) {
	slog("\"/var/cache/he-ipv4.yml\" doesn't exist. attempting to create file", 3);
	ymlCreate();
}

my ($fileURL, $fileIP) = ymlGet();
if ($debug == 5) { say("from file: fileURL: " . $fileURL . " | fileIP " . $fileIP); }

if ($fileURL !~ /^[0-9]*$/) { $fileURL = 0; }
if ($fileIP !~ /$regexIP/) { $fileIP = "127.0.0.1" }
if ($debug == 5) { say("post sanity: fileURL: " . $fileURL . " | fileIP " . $fileIP); }

my $urlLen = @listURL;
my $urlNum;

if ($fileURL + 1 >= $urlLen ) { $urlNum = 0; } else { $urlNum = $fileURL + 1; }
if ($debug == 5) { say("urlLen: " . $urlLen . " | urlNum: ". $urlNum); }

my ($extIP, $urlUsed) = getExtIP($urlNum, \@listURL);
if ($debug == 5) { say("extIP: " . $extIP . " | urlUsed: " . $urlUsed); }

if ($extIP ne $fileIP) {
	updateIP($extIP);
	ymlWrite($urlUsed, $extIP);
	slog("the endpoint IPv4 address has been upated to " . $extIP, 3);
} else { 
	ymlWrite($urlUsed, $extIP);
	slog("the external IP address (" . $extIP . ") has not changed", 3);
}

###############
# SUBROUTINES #
###############
sub slog {
	if ($debug >= 1) {
		my $message = shift;
		my $level = shift;
		my $lvl = $level;
		switch ($level) {
			case 3 {
				if ($level <= $debug) { info($message); }
			}
			case 2 {
				if ($level <= $debug) { warning($message); }
			}
			case 1 {
				if ($level <= $debug) { error($message); }
			}
			else { warning("incorrect value used for message level on subroutine slog call on line " . __LINE__); }
		}
		if ($debug >= 4) { 
			my $prefix;
			if ($lvl == 1) { $prefix = "[error] "; }
			elsif ($lvl == 2) { $prefix = "[warning] "; }
			elsif ($lvl == 3) { $prefix = "[info] "; }
			say($prefix . $message); 
		}
	}
}

sub ymlCreate {
	my $yaml = YAML::Tiny->new;
	$yaml->[0]->{ipv4} = '127.0.0.1';
	$yaml->[0]->{url} = '9001';
	$yaml->write($configFile);
	if (-e $configFile) {
		slog("file created successfully", 3);
	} else {
		slog("crap, something didn't go as planned. file does not appear to have been created. exiting", 1);
		exit 1;
	}
}

sub ymlGet {
	my $yaml = YAML::Tiny->new;
	$yaml = YAML::Tiny->read($configFile);
	my $url = $yaml->[0]->{url};
	my $ip = $yaml->[0]->{ipv4};
	return($url, $ip);
}

sub ymlWrite {
	my ($url, $ipv4) = @_;
	my $yaml = YAML::Tiny->new;
	$yaml->[0]->{ipv4} = $ipv4;
	$yaml->[0]->{url} = $url;
	$yaml->write($configFile);
	$yaml->[0]->{url} = $url;
	$yaml->write($configFile);
}

sub getExtIP {
	my ($index, $list) = @_;
	my $extIP;
	my $run = 1;
	my $status;
	my $mech = WWW::Mechanize->new(
		agent=>"curl/7.21.0 (i486-pc-linux-gnu) libcurl/7.21.0 WWW-Mechanize/1.71 (theckman/he-ipv4.pl)",
		onerror=>sub { slog("something happened when trying to connect to " . $list->[$index], 2); } );
	
	while ($run <= 4) {		
		$mech->get($list->[$index]);
		$extIP = $mech->content(format=>'text');
		
		if ($extIP !~ /$regexIP/ && $mech->status() == 200) {
			slog("incorrect value obtained from " . $list->[$index] . ". trying next url", 2);
			next;
		} elsif ($run == 4 && $extIP !~ /$regexIP/) {
			slog("unable to determine external IP address for some reason. do you have an active network connection? exiting", 1);
			exit 1;
		} elsif ($extIP =~ /$regexIP/ && $mech->status() == 200) {  $extIP = $1; last; }
		
	} continue {
		if ($index + 1 == @$list ) { $index = 0; } else { $index++; };
		$run++;
	}
	return ($extIP, $index);
}

sub updateIP {
	my $IPV4 = $_[0];
	my $url = "https://ipv4.tunnelbroker.net/ipv4_end.php?apikey=" . $userID . "&pass=" . $userPass . "&ip=" . $IPV4 . "&tid=" . $tunnelID;
	my $mech = WWW::Mechanize->new(
		agent=>"curl/7.21.0 (i486-pc-linux-gnu) libcurl/7.21.0 WWW-Mechanize/1.71 (theckman/he-ipv4.pl)",
		onerror=>sub { slog("something happened when trying to connect to http://ipv4.tunnelbroker.net", 2); } );
	$mech->get($url);	
	if ($debug == 5) { say("url: " . $url); }
	if ($debug == 5) { say("output: " . $mech->content(format=>'text')); }
}