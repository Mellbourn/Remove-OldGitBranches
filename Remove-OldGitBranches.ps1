<#
.SYNOPSIS

  Removes old remote branches in git. Either locally or from the origin remote

.DESCRIPTION

  Since we use a lot of feature branches, many of which are pushed, we end up with a lot of remote branches. This is confusing and unwieldy in the git GUIs.
  For this reason, this script should be run every now and then to clean up branches.

.NOTES

You may get the following errors that can be ignored (for some reason git seems to return error message when it successfully deletes a branch)

At .\Remove-OldGitBranches.ps1:50 char:3
+   git push origin --delete $_.Name
+   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
 - [deleted]         defect/Duplicates

.EXAMPLE

  .\Remove-OldGitBranches.ps1 -age 100 -force -remote

  Remove branches older than 100 days from the remote and do not prompt the user before doing it.

.EXAMPLE

  .\Remove-OldGitBranches.ps1 -deleteUnmerged

  Will remove even branches that have not been merged to master. This will cause loss of historical information, since those commits will no longer have any branch pointer to them.

.LINK 
  http://git-scm.com/docs/git-branch
#>

param(
      # Remove old branches without pausing
      [Parameter()][switch]$force,

      # Number of days old a branch must be to be deleted
      [Parameter()][string]$age = 14,

      # Dangerous! This will remove even branches that have not been merged to master. This will cause loss of historical information, since those commits will no longer have any branch pointer to them.
      [Parameter()][switch]$deleteUnmerged,

      # run this on remote branches instead of local
      [Parameter()][switch]$remote
)

Function Parse-GitDate($gitdate) {
  return [DateTime]::Parse($gitdate)
}

Function Remove-Asterisk($branch) {
  $branchString = $branch.ToString();
  if($branchString -match "^\* ") {
    return $branchString.SubString(2);
  } else {
    return $branchString;
  }
}

$remoteName = "origin"

# make sure we have all remote branches
git fetch -p $remoteName

$remotePath = ($remoteName + "/")

if ($remote) {
  $branchParameter = "-r"
} else {
  $branchParameter = "--list"
}

if ($deleteUnmerged) {
  $mergeParameter = "--no-merged"
} else {
  $mergeParameter = "--merged"
}

$remoteBranches = git branch $branchParameter $mergeParameter master | 
  ForEach-Object { $_.ToString().Trim() } | 
  ForEach-Object { Remove-Asterisk $_ } | 
  select-string -pattern "release/|origin/master|master$|git-backify" -NotMatch |
  ForEach-Object { $_.ToString() } | 
  Where-Object { (-not $remote) -or $_.ToString().StartsWith($remotePath) } |
  ForEach-Object {
      if($remote) {
        $name = $_.SubString($remotePath.Length);
      } else {
        $name = $_;
      }
      $properties = @{
        'Name'= $name;
        'Hash'= (git rev-parse $_);
        'Date'= Parse-GitDate (git show -s --format=%ci (git rev-parse $_));
      }
      New-Object PSObject –Prop $properties 
  } | 
  Where-Object { ([DateTime]::Today - $_.Date).TotalDays -ge $age } | 
  Sort-Object Date

if($remoteBranches.Length -eq 0) {
  exit
}

if($remote) {
  Write-Host ("About to delete the following branches from " + $remoteName)
} else {
  Write-Host ("About to delete the following local branches")
}
$remoteBranches | Format-Table -Auto | Out-String -Width 256

if(-not $force) {
    Write-Host -NoNewLine 'Press return to continue or break to exit...';
    Read-Host
}

$ErrorActionPreference = 'continue'

$remoteBranches | ForEach-Object {
  if ($remote) {
    git push $remoteName --delete $_.Name
  } else {
    if ($deleteUnmerged) {
      $dParameter = "-D"
    } else {
      $dParameter = "-d"
    }
    git branch $dParameter $_.Name
  }
}

$ErrorActionPreference = 'stop'

git remote prune $remoteName