#!/usr/bin/perl

################################################################################
#
# git_diff.pl
#     Provides a simple (ASCII) UI for diffing commits in Git in Linux.
#
# Author
#     mats.lintonsson@ericsson.com
#
# Todo (highest prio in top, roughly):
#     - Make it possible to use HEAD for commitSec.
#     - Document how the configuration file works.
#     - Show branches and tags in the UI?
#     - Add search abilities in the UI?
#     - Make UI more robust (seems to be scrolling problems, or?).
#     - Clean TODOs.
#     - Add examples to the help text.
#
# History
#     2014-12-01  ervmali  First version.
#     2014-12-02  ervmali  Introduced the UNCOMMITTED functionality.
#     2014-12-03  ervmali  Added the configuration file functionality.
#     2014-12-09  ervmali  Bug fixes.
#     2015-01-12  ervmali  Added a simple UI for picking commits to diff.
#     2015-01-13  ervmali  Updated the printHelp sub.
#     2015-01-14  ervmali  Now possible to select uncommitted changes in the UI.
#     2015-01-15  ervmali  Added the next ('n') jump functionality.
#     2015-02-18  ervmali  Added new parameter: --diff-all
#
################################################################################

use FindBin;                      # where was script installed?
use lib "$FindBin::Bin/modules";  # use a sub-dir for libs
require Term::Screen;
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
  print("\ngit_diff.pl\n\n");
  print("  Provides a simple interface for diffing commits in Git in Linux.\n\n");

  print("Usage:\n\n");

  print("  Variant one:\n");
  print("    git_diff.pl <commitRef> <commitSec> [--diff-all]\n\n");

  print("  Variant two:\n");
  print("    git_diff.pl HEAD <commitSec> [--diff-all]\n\n");

  print("  Variant three:\n");
  print("    git_diff.pl UNCOMMITTED <commitSec> [--diff-all]\n\n");

  print("  Variant four:\n");
  print("    git_diff.pl --graph\n\n");

  print("Details:\n\n");

  print("  <commitRef> and <commitSec> represent commits given by their respective SHA-1s\n");
  print("  (partly or in their entirety).\n\n");

  print("  <commitRef> is the so called reference commit, i.e. the commit containing the\n");
  print("  modifications that will be subject for diffing against.\n\n");

  print("  <commitSec> is the so called secondary commit, i.e. the commit that will diff\n");
  print("  against the modifications in <commitRef>.\n\n");

  print("  Special labels:\n\n");

  print("    HEAD:        May be used as a substitution for <commitRef>. The SHA-1 is\n");
  print("                 fetched automatically, taking the commit where HEAD currently\n");
  print("                 is located.\n\n");

  print("    UNCOMMITTED: May be used as a substitution for <commitRef>. The uncommitted\n");
  print("                 modifications (excluding untracked files) will then be used\n");
  print("                 instead of a real commit.\n\n");

  print("  If --graph is used, a simple (ASCII) UI is started. A commit tree is shown.\n");
  print("  Use the UI to select a reference commit and a secondary commit. The following\n");
  print("  keys are valid for navigation within the UI:\n\n");

  print("    k = Moves arrow (to the left of the screen) up.\n");
  print("    j = Moves arrow (to the left of the screen) down.\n");
  print("    K = Paging up ten lines.\n");
  print("    J = Paging down ten lines.\n");
  print("    r = Sets the reference commit at the commit next to the arrow. Indicated in\n");
  print("        the UI by an 'R' on the left side of the screen.\n");
  print("    s = Sets the secondary commit at the commit next to the arrow. Indicated in\n");
  print("        the UI by a 'S' on the left side of the screen.\n");
  print("    d = Starts the diffing.\n");
  print("    D = Same as d, but invoking the --diff-all functionality (see below).\n");
  print("    q = Quits the UI/script.\n\n");

  print("  If the optional parameter --diff-all is used, not only modifications from the\n");
  print("  <commitRef> is brought into the diff, but also all modifications between the\n");
  print("  <commitRef> and <commitSec> (excl. modifications in <commitSec> itself).\n\n");
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

# ------------------------------------------------------------------------------
# Returns a number of commits obtained from a one-line 'git log' command.
#
# Arguments:
#   $_[0] = offset (from what commit to start obtain)
#   $_[1] = number of commits to obtain
#
# Returns:
#   A list of commits, delimited by a newline character.
# ------------------------------------------------------------------------------
sub getGitCommits
{
  my $offset = $_[0];
  my $number = $_[1];

  if($offset < 0)
  {
    $offset = 0;
  }

  if($number < 0)
  {
    $number = 0;
  }

  return `git log --all --skip=${offset} -${number} --graph --abbrev-commit --decorate --format=format:'%h (%cd) %s [%an]'`;
}

# ------------------------------------------------------------------------------
# Checks if there are more Git commits to fetch (with 'git log') from a certain
# offset.
#
# Arguments:
#   $_[0] = offset (from what commit to start checking)
#   $_[1] = number of commits to obtain
#
# Returns:
#   1 if there are more commits, otherwise 0
# ------------------------------------------------------------------------------
sub moreGitCommits
{
  my $returnValue = 1;
  my $offset = $_[0];
  my $number = $_[1];

  if($offset < 0)
  {
    $offset = 0;
  }

  if($number < 0)
  {
    $number = 0;
  }

  my @commits = `git log --all --skip=${offset} -${number} --graph --abbrev-commit --decorate --format=format:'%h (%cd) %s [%an]'`;

  if(scalar(@commits) == 0)
  {
    $returnValue = 0;
  }

  return $returnValue;
}


# == main ======================================================================

print("\n");

# global definitions

my $commitRef = "";  # reference commit
my $commitSec = "";  # secondary commit
my @commitRefFiles;  # a list of all modified files found in $commitRef
my $diffAllFilesBetweenTwoCommits = 0;

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

my $numOfArgs = scalar(@ARGV);

if($numOfArgs == 1)
{
  if($ARGV[0] =~ /^--graph$/)
  {
    # get terminal size

    (my $lines, my $cols) = `stty size`=~/(\d+)\s+(\d+)/?($1,$2):(80,25);

    if($lines < 10 or $cols < 80)
    {
      print("ERROR! Terminal too small. Not enough lines or width to run the UI.\n");
      exit(1);
    }

    # create a screen object for the UI

    my $screen = new Term::Screen;
    $screen->clrscr();
    $screen->noecho();

    my @logLines;
    my $offset = 0;
    my $arrow = 0;
    my $loop = 1;
    my $numAvailableLines = $lines - 2;
    my $previousRefCommitLine = -1;
    my $previousSecCommitLine = -1;

    while($loop == 1)  # loop until user breaks
    {
      @logLines = ();

      my $uncommittedChanges = 0;
      if($offset == 0 and `git status --porcelain | awk '{if (\$1 == "M") print \$2}'` ne "")  # check if there are any uncommitted changes in the repo
      {
        $uncommittedChanges = 1;
      }

      @logLines = getGitCommits($offset, $numAvailableLines - ($uncommittedChanges == 1 ? 1 : 0));  # fetch commits from the Git logs

      if($uncommittedChanges == 1)
      {
        unshift(@logLines, "* UNCOMMITTED CHANGES");  # add a uncommitted "commit" tag as the first "commit" in the list of commits
      }

      my $currentLine = 0;
      foreach my $oneLogLine (@logLines)  # print a set of commits
      {
        $oneLogLine = trimString($oneLogLine);
        $screen->at($currentLine,3)->puts(substr($oneLogLine, 0, $cols - 7));  # print one line

        if($commitRef ne "" and ($oneLogLine =~ /\*\s${commitRef}\s\(/ or ($oneLogLine =~ /\*\sUNCOMMITTED CHANGES/ and $commitRef eq "UNCOMMITTED")))  # print 'R' if this commit has been marked as the reference commit
        {
          $screen->at($currentLine,1)->puts("R");
        }

        if($commitSec ne "" and $oneLogLine =~ /\*\s${commitSec}\s\(/)  # print 'S' if this commit has been marked as the secondary commit
        {
          $screen->at($currentLine,1)->puts("S");
        }

        $currentLine++;

        if($currentLine >= $numAvailableLines)  # have we reached the limit of available lines?
        {
          last;
        }
      }

      if($currentLine < $numAvailableLines)  # check if the commit history is shorter if the number of available lines
      {
        $numAvailableLines = $currentLine;
      }

      $currentLine++;
      $screen->at($currentLine,0)->puts("Legend: [k=up] [j=down] [K=pgUp] [J=pgDown] [r=ref] [s=sec] [d/D=diff] [q=quit]");

      WAIT_FOR_USER_INPUT:

      $screen->at($arrow,0)->puts(">");
      $screen->at($lines,$cols);  # put cursor in lower-right corner

      my $key = $screen->getch();

      # examine pressed key

      if($key eq "q")
      {
        $screen->clrscr();
        exit(0);
      }
      elsif($key eq "j")
      {
        $screen->at($arrow,0)->puts(" ");  # clear previous arrow
        $arrow++;

        if($arrow >= $numAvailableLines)
        {
          $arrow = $numAvailableLines - 1;
        }

        goto WAIT_FOR_USER_INPUT;  # bypass reprint of all commits
      }
      elsif($key eq "k")
      {
        $screen->at($arrow,0)->puts(" ");  # clear previous arrow
        $arrow--;

        if($arrow < 0)
        {
          $arrow = 0;
        }

        goto WAIT_FOR_USER_INPUT;  # bypass reprint of all commits
      }
      elsif($key eq "J")
      {
        if(moreGitCommits($offset + 10, $numAvailableLines))
        {
          $screen->clrscr();
          $offset = $offset + 10;
        }
      }
      elsif($key eq "K")
      {
        $screen->clrscr();
        $offset = $offset - 10;

        if($offset < 0)
        {
          $offset = 0;
        }
      }
      elsif($key eq "r")
      {
        if($logLines[$arrow] =~ /\*\s([0-9a-z]{7})\s\(/ or $logLines[$arrow] =~ /\*\s(UNCOMMITTED) CHANGES/)  # make sure the arrow line contains a commit
        {
          my $commitTemp = $1;

          if($commitTemp ne $commitSec and $commitTemp ne $commitRef)  # only "approve" reference commit if it's not the same commit as the secondary, or itself
          {
            if($previousRefCommitLine != -1)
            {
              $screen->at($previousRefCommitLine,1)->puts(" ");  # clean old 'R'
            }

            $commitRef = $commitTemp;
            $previousRefCommitLine = $arrow;
          }
        }
      }
      elsif($key eq "s")
      {
        if($logLines[$arrow] =~ /\*\s([0-9a-z]{7})\s\(/)  # make sure the arrow line contains a commit
        {
          my $commitTemp = $1;

          if($commitTemp ne $commitRef and $commitTemp ne $commitSec)  # only "approve" secondary commit if it's not the same commit as reference, or itself
          {
            if($previousSecCommitLine != -1)
            {
              $screen->at($previousSecCommitLine,1)->puts(" ");  # clean old 'S'
            }

            $commitSec = $commitTemp;
            $previousSecCommitLine = $arrow;
          }
        }
      }
      elsif($key eq "d")
      {
        $loop = 0;
      }
      elsif($key eq "D")
      {
        $loop = 0;
        $diffAllFilesBetweenTwoCommits = 1;
      }
      else  # user pressed an unsupported key
      {
        goto WAIT_FOR_USER_INPUT;  # bypass reprint of all commits
      }
    }

    $screen->clrscr();
    undef $screen;

    if($commitRef eq "" or $commitSec eq "")
    {
      print("ERROR! Cannot diff. The reference and/or secondary commits were not set.\n\n");
      exit(1);
    }
  }
  else
  {
    print("ERROR! Can't recognize $ARGV[0] as an argument.\n");
    printHelp();
    exit(1);
  }
}
elsif($numOfArgs == 2 or $numOfArgs == 3)
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

  if($commitSec =~ /HEAD/)
  {
      print("ERROR! Cannot use the HEAD word for the secondary commit.\n");
      printHelp();
      exit(1);
  }

  if($numOfArgs == 3)
  {
    if($ARGV[2] =~ /^--diff-all$/)
    {
      $diffAllFilesBetweenTwoCommits = 1;
    }
    else
    {
      print("ERROR! Can't recognize $ARGV[2] as an argument.\n");
      printHelp();
      exit(1);
    }
  }
}
else
{
  print("ERROR! Faulty number of arguments.\n");
  printHelp();
  exit(1);
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

# check that reference and secondary commit are not the same

if($commitRef =~ /^${commitSec}/)
{
  print("ERROR! The two given commits have the same SHA-1 (${commitRef}). Nothing to diff.\n\n");
  exit(1);
}

# get files that have been modified in reference commit (and possibly all files therebetween)

if($commitRef eq "UNCOMMITTED")
{
  @commitRefFiles = `git status --porcelain | awk '{if (\$1 == "M") print \$2}'`;

  if($diffAllFilesBetweenTwoCommits == 1)  # get a list of files modified between the reference commit (emulated to HEAD) and the secondary commit (incl. the secondary commit)
  {
    my $commitHead = `git rev-parse HEAD`;
    $commitHead = trimString($commitHead);

    my @allFilesBetweenTwoCommits = `git diff --name-only ${commitHead} ${commitSec}`;
    @commitRefFiles = (@commitRefFiles, @allFilesBetweenTwoCommits);
  }
}
else
{
  @commitRefFiles = `git diff-tree --no-commit-id --name-only -r ${commitRef}`;  # get a list of files modified in the reference commit

  if($diffAllFilesBetweenTwoCommits == 1)  # get a list of files modified between the reference commit and the secondary commit (incl. the secondary commit)
  {
    my @allFilesBetweenTwoCommits = `git diff --name-only ${commitRef} ${commitSec}`;
    @commitRefFiles = (@commitRefFiles, @allFilesBetweenTwoCommits);
  }
}

# remove unwanted white spaces from the entries in the list of files

foreach my $file (@commitRefFiles)
{
  $file = trimString($file);
}

# remove any duplicates in the list of files to diff and check that the list is not empty

my %tempHash = map { $_, 1 } @commitRefFiles;
@commitRefFiles = keys %tempHash;

if(scalar(@commitRefFiles) == 0)
{
  print("ERROR! ${commitRef} does not contain any modified files.\n\n");
  exit(1);
}

# main loop where user is presented with files that can be diffed and he/she makes a choice

my $loop = 1;
my $nextFileToDiff = 0;
my $stdin;

while($loop == 1)
{
  # print files that can be diffed

  my $file;
  my $i = 0;
  my $marker;
  foreach $file (@commitRefFiles)
  {
    $marker = "";
    if($i == $nextFileToDiff)
    {
      $marker = "*";  # indicates the next commit (for the 'n' usage)
    }

    print("(${i}${marker}) ${file}\n");
    $i++;
  }

  # wait for user input

  print("\nOptions:" );
  print("\n  - (number) : Pick a diff.");
  print("\n  - n        : Pick next diff. Indicated by a star.");
  print("\n  - q        : Quit script.");
  print("\nAction? ");

  $stdin = <STDIN>;
  $stdin = trimString($stdin);

  # examine the user input

  if( $stdin =~ /^n$/ )  # n (next)
  {
      $stdin = $nextFileToDiff;
      goto DIFF;
  }
  elsif( $stdin =~ /^q$/ )  # q (quit)
  {
      $loop = 0;
  }
  elsif( $stdin =~ /^\d+$/ )  # a number (file to diff)
  {
    # check that the user has given a valid number

    if($stdin >= 0 and $stdin <= scalar(@commitRefFiles)-1)
    {
      $nextFileToDiff = $stdin;

      DIFF:

      $nextFileToDiff++;

      if($nextFileToDiff > (scalar(@commitRefFiles) - 1))
      {
        $nextFileToDiff = 0;
      }

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
