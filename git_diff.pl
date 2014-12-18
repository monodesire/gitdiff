#!/usr/bin/perl

################################################################################
#
# git_diff.pl
#     Provides a simple non-graphical UI for diffing commits in Git in Linux.
#
# Author
#     mats.lintonsson@ericsson.com
#
# Todo (highest prio in top, roughly):
#     - Make it possible to use HEAD for commitSec.
#     - Introduce command 'n' (next) for auto-jumping to the next file.
#     - Document how the configuration file works.
#     - Clean TODOs.
#
# Dreaming:
#     - Create a (G)UI for easy viewing and selecting commits.
#
# History
#     2014-12-01  ervmali  First version.
#     2014-12-02  ervmali  Introduced the UNCOMMITTED functionality.
#     2014-12-03  ervmali  Added the configuration file functionality.
#     2014-12-09  ervmali  Bug fixes.
#
################################################################################

use warnings;
use strict;


# == subs ======================================================================

# ------------------------------------------------------------------------------
# Prints a short how-to-use guide to the user.
#
# Arguments:
#   N/A
#
# Returns:
#   N/A
# ------------------------------------------------------------------------------
sub printHelp
{
  print("\nUsage:\n\n");

  print("  Variant one:\n");
  print("    git_diff.pl <commitRef> <commitSec>\n\n");

  print("  Variant two:\n");
  print("    git_diff.pl HEAD <commitSec>\n\n");

  print("  Variant three:\n");
  print("    git_diff.pl UNCOMMITTED <commitSec>\n\n");

  print("  Where <commitRef> is the SHA-1 (or the beginning of it) of the\n");
  print("  reference commit, i.e. the commit containing the changes that will\n");
  print("  be subject for diff against <commitSec>.\n\n");

  print("  Use the word HEAD as a substitution for <commitRef>. The commit is\n");
  print("  then fetched automatically, taking the commit where HEAD is\n");
  print("  located.\n\n");

  print("  Use the word UNCOMMITTED as a substitution for <commitRef>. The\n");
  print("  uncommitted modifications (excluding untracked files) will then\n");
  print("  be used instead of a real commit.\n\n");
}

# ------------------------------------------------------------------------------
# Removes any leading and/or trailing whitespaces of a string.
#
# Arguments:
#   $_[0] = the string to trim
#
# Returns:
#   The string from $_[0] but without any leading and trailing whitespaces.
# ------------------------------------------------------------------------------
sub trimString
{
  my $returnString = "";

  if(scalar(@_) == 1)
  {
    $returnString = $_[0];
    $returnString =~ s/^\s+//;  # remove any leading whitespaces
    $returnString =~ s/\s+$//;  # remove any trailing whitespaces
  }

  return $returnString;
}


# == main ======================================================================

print("\n");

# global definitions

my $commitRef = "";  # reference commit
my $commitSec = "";  # secondary commit
my @commitRefFiles;  # a list of all modified files found in $commitRef

my $repoRoot = `git rev-parse --show-toplevel`;  # Git repository root directory  # TODO: Add fault handling for this operation.
$repoRoot = trimString($repoRoot);
$repoRoot = "${repoRoot}/";

my $user = `whoami`;  # user-id
$user = trimString($user);

my $homePath = `echo ~${user}`;  # user's home directory path
$homePath = trimString($homePath);

my $configFile = "${homePath}/.git_diff_config";  # path and filename of configuration file

# global definitions that are configurable via the .git_diff_config configuration file

my $diffTool = "vim -d FILE_REF FILE_SEC";  # during runtime FILE_REF and FILE_SEC will be replaced automatically by real filenames
my $tmpStorage = "/tmp/";

# read config file (it it exists)

if(-e ${configFile})
{
  # configuration file found; read it and set parameters accordingly

  open(INFILE, "${configFile}" ) or die ( "ERROR! Couldn't open ${configFile}: $!");

  while(<INFILE>)  # get one line at the time from the configuration file
  {
    # $_ now contains one line from INFILE

    if( /^\s*diffTool\s*=\s*(.*)$/ )  # reading the diffTool parameter
    {
      $diffTool = trimString($1);
    }
    elsif(/^\s*tmpStorage\s*=\s*(.*)$/)  # reading the tmpStorage parameter
    {
      $tmpStorage = trimString($1);
    }
  }

  close(INFILE);
}

# check arguments

if(scalar(@ARGV) != 2)
{
  print("ERROR! Faulty number of arguments.\n");
  printHelp();
  exit(1);
}
else
{
  if($ARGV[0] =~ /^HEAD$/)
  {
    $commitRef = `git rev-parse HEAD`;  # get commitRef from current checked out commit
  }
  elsif($ARGV[0] =~ /^UNCOMMITTED$/)
  {
    $commitRef = "UNCOMMITTED";
  }
  else
  {
    $commitRef = $ARGV[0];
  }

  $commitSec = $ARGV[1];
}

$commitRef = trimString($commitRef);
$commitSec = trimString($commitSec);

# check that we are in Git

if(not `git rev-parse --is-inside-work-tree 2>/dev/null` =~ /true/)
{
  print("ERROR! Current directory does not belong to a Git repo.\n\n");
  exit(1);
}

# verify the commits

if($commitRef ne "UNCOMMITTED" and not `git cat-file -t ${commitRef} 2>/dev/null` =~ /commit/)
{
  print("ERROR! ${commitRef} is not a valid commit.\n\n");
  exit(1);
}

if(not `git cat-file -t ${commitSec} 2>/dev/null` =~ /commit/)
{
  print("ERROR! ${commitSec} is not a valid commit.\n\n");
  exit(1);
}

# get files that have been modified in reference commit

if($commitRef eq "UNCOMMITTED")
{
  @commitRefFiles = `git status --porcelain | awk '{if (\$1 == "M") print \$2}'`;
}
else
{
  @commitRefFiles = `git diff-tree --no-commit-id --name-only -r ${commitRef}`;
}

if(scalar(@commitRefFiles) == 0)
{
  print("ERROR! ${commitRef} does not contain any modified files.\n\n");
  exit(1);
}

# main loop where user is presented with files that can be diffed and he/she makes a choice

my $loop = 1;
my $stdin;

while( $loop == 1 )
{
  # print files that can be diffed

  my $file;
  my $i = 0;
  foreach $file (@commitRefFiles)
  {
    $file = trimString($file);
    print("($i) ${file}\n");
    $i++;
  }

  # wait for user input

  print( "\nPick a number (or use q to exit)? " );

  $stdin = <STDIN>;
  $stdin = trimString($stdin);

  # examine the user input

  if( $stdin =~ /^q$/ )  # q (quit)
  {
      $loop = 0;
  }
  elsif( $stdin =~ /^\d+$/ )  # a number (file to diff)
  {
    # check that the user has given a valid number

    if($stdin >= 0 and $stdin <= scalar(@commitRefFiles)-1)
    {
      my $diffToolTemp = $diffTool;

      # find out the name of the chosen file

      my $currentFilename = "UNKNOWN";
      if($commitRefFiles[$stdin] =~ /(\w+\.\w+)$/)
      {
        $currentFilename = $1;
      }

      # get file content from reference commit

      my $fileRef = "${tmpStorage}/tmp.${user}.commitRef.${currentFilename}";

      if($commitRef eq "UNCOMMITTED")
      {
        my $result = `cat ${repoRoot}/$commitRefFiles[$stdin] > ${fileRef}`;
      }
      else
      {
        my $result =`git show ${commitRef}:$commitRefFiles[$stdin] > ${fileRef}`;
      }

      # get file content from secondary commit

      my $fileSec = "${tmpStorage}/tmp.${user}.commitSec.${currentFilename}";
      my $result =`git show ${commitSec}:$commitRefFiles[$stdin] > ${fileSec} 2>/dev/null`;

      # start the diff tool with the two files

      $diffToolTemp =~ s/FILE_REF/${fileRef}/;
      $diffToolTemp =~ s/FILE_SEC/${fileSec}/;

      system(${diffToolTemp});

      # remove temporary files

      unlink(${fileRef});
      unlink(${fileSec});
    }
  }

  print("\n");
}

exit(0);
