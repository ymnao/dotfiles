# Git Aliases for PowerShell
# Fish-style git shortcuts
#
# WARNING: These aliases override some built-in PowerShell aliases:
#   gc  (Get-Content)      -> git commit      (use 'Get-Content' or 'cat' instead)
#   gp  (Get-ItemProperty) -> git push        (use 'Get-ItemProperty' instead)
#   gl  (Get-Location)     -> git log         (use 'Get-Location' or 'pwd' instead)
#
# To disable specific aliases, comment them out or create config.local.ps1 with:
#   Remove-Item Alias:gc -Force -ErrorAction SilentlyContinue

#---------------------------------------------------------------
# Basic Operations
#---------------------------------------------------------------

function gs { git status $args }
function ga { git add $args }
function gaa { git add --all $args }
function gap { git add --patch $args }

function gc { git commit $args }
function gcm { git commit -m $args }
function gca { git commit --amend $args }
function gcam { git commit --amend -m $args }
function gcan { git commit --amend --no-edit $args }

function gcv { git commit -v $args }
function gcvm { git commit -v -m $args }

#---------------------------------------------------------------
# Branch Operations
#---------------------------------------------------------------

function gb { git branch $args }
function gba { git branch -a $args }
function gbd { git branch -d $args }
function gbD { git branch -D $args }
function gbm { git branch -m $args }
function gbr { git branch -r $args }

function gco { git checkout $args }
function gcob { git checkout -b $args }
function gcom { git checkout main $args }
function gcod { git checkout develop $args }

function gsw { git switch $args }
function gswc { git switch -c $args }
function gswm { git switch main $args }
function gswd { git switch develop $args }

#---------------------------------------------------------------
# Remote Operations
#---------------------------------------------------------------

function gp { git push $args }
function gpf { git push --force-with-lease $args }
function gpo { git push origin $args }
function gpom { git push origin main $args }
function gpu { git push -u origin HEAD $args }

function gpl { git pull $args }
function gplr { git pull --rebase $args }
function gplo { git pull origin $args }

function gf { git fetch $args }
function gfa { git fetch --all --prune $args }
function gfo { git fetch origin $args }

function gr { git remote $args }
function grv { git remote -v $args }
function gra { git remote add $args }
function grr { git remote remove $args }
function gru { git remote update $args }

#---------------------------------------------------------------
# Diff & Log
#---------------------------------------------------------------

function gd { git diff $args }
function gds { git diff --staged $args }
function gdc { git diff --cached $args }
function gdw { git diff --word-diff $args }

function gl { git log --oneline $args }
function glo { git log --oneline --graph $args }
function glg { git log --graph --decorate --all $args }
function gla { git log --graph --decorate --all --oneline $args }
function glp { git log -p $args }
function gls { git log --stat $args }

function gshow { git show $args }

#---------------------------------------------------------------
# Merge & Rebase
#---------------------------------------------------------------

function gm { git merge $args }
function gma { git merge --abort $args }
function gmc { git merge --continue $args }
function gmm { git merge main $args }
function gmd { git merge develop $args }

function grb { git rebase $args }
function grba { git rebase --abort $args }
function grbc { git rebase --continue $args }
function grbs { git rebase --skip $args }
function grbm { git rebase main $args }
function grbd { git rebase develop $args }
function grbi { git rebase -i $args }

#---------------------------------------------------------------
# Stash
#---------------------------------------------------------------

function gst { git stash $args }
function gsta { git stash apply $args }
function gstp { git stash pop $args }
function gstl { git stash list $args }
function gsts { git stash show -p $args }
function gstd { git stash drop $args }
function gstc { git stash clear $args }

#---------------------------------------------------------------
# Reset & Clean
#---------------------------------------------------------------

function grh { git reset HEAD $args }
function grhs { git reset HEAD --soft $args }

# WARNING: Destructive command - discards all uncommitted changes
function grhh {
    Write-Host "WARNING: This will discard all uncommitted changes!" -ForegroundColor Red
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -eq 'y') { git reset HEAD --hard $args }
}

# WARNING: Destructive command - deletes untracked files
function gclean {
    Write-Host "WARNING: This will delete untracked files!" -ForegroundColor Red
    git clean -fd --dry-run
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -eq 'y') { git clean -fd $args }
}

# WARNING: Destructive command - deletes untracked files including ignored
function gcleanx {
    Write-Host "WARNING: This will delete ALL untracked files (including ignored)!" -ForegroundColor Red
    git clean -fdx --dry-run
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -eq 'y') { git clean -fdx $args }
}

# WARNING: Destructive command - resets to pristine state
function gpristine {
    Write-Host "WARNING: This will discard ALL changes and untracked files!" -ForegroundColor Red
    Write-Host "  - git reset --hard" -ForegroundColor Yellow
    Write-Host "  - git clean -fdx" -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -eq 'y') {
        git reset --hard
        git clean -fdx
    }
}

#---------------------------------------------------------------
# Cherry-pick & Revert
#---------------------------------------------------------------

function gcp { git cherry-pick $args }
function gcpa { git cherry-pick --abort $args }
function gcpc { git cherry-pick --continue $args }

function grev { git revert $args }
function greva { git revert --abort $args }
function grevc { git revert --continue $args }

#---------------------------------------------------------------
# Clone & Init
#---------------------------------------------------------------

function gcl { git clone $args }
function gcls { git clone --depth 1 $args }
function ginit { git init $args }

#---------------------------------------------------------------
# Tags
#---------------------------------------------------------------

function gt { git tag $args }
function gtl { git tag -l $args }
function gta { git tag -a $args }
function gtd { git tag -d $args }
function gtp { git push --tags $args }

#---------------------------------------------------------------
# Submodules
#---------------------------------------------------------------

function gsub { git submodule $args }
function gsubu { git submodule update --init --recursive $args }

#---------------------------------------------------------------
# Worktree
#---------------------------------------------------------------

function gwt { git worktree $args }
function gwtl { git worktree list $args }
function gwta { git worktree add $args }
function gwtr { git worktree remove $args }

#---------------------------------------------------------------
# Bisect
#---------------------------------------------------------------

function gbs { git bisect $args }
function gbss { git bisect start $args }
function gbsg { git bisect good $args }
function gbsb { git bisect bad $args }
function gbsr { git bisect reset $args }

#---------------------------------------------------------------
# Misc
#---------------------------------------------------------------

function gblame { git blame $args }
function gignore { git update-index --assume-unchanged $args }
function gunignore { git update-index --no-assume-unchanged $args }
function gcount { git shortlog -sn $args }
