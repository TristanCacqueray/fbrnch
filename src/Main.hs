module Main (main) where

import Common

import Distribution.Fedora.Branch
import Options.Applicative (eitherReader, ReadM)
import SimpleCmd
import SimpleCmd.Git
import SimpleCmdArgs
import System.IO (BufferMode(NoBuffering), hSetBuffering, hIsTerminalDevice, stdin, stdout)

-- commands
import Cmd.Bugs
import Cmd.Build
import Cmd.Clone
import Cmd.Import
import Cmd.Merge
import Cmd.PkgReview
import Cmd.Pull
import Cmd.RequestBranch
import Cmd.RequestRepo
import Cmd.Reviews
import Cmd.Status
import Cmd.Switch

import Bugzilla (testBZlogin)
import ListReviews
import Package (Package)
import Paths_fbrnch (version)

main :: IO ()
main = do
  tty <- hIsTerminalDevice stdin
  when tty $ hSetBuffering stdout NoBuffering
  activeBranches <- getFedoraBranches
  gitdir <- isGitDir "."
  dispatchCmd gitdir activeBranches

dispatchCmd :: Bool -> [Branch] -> IO ()
dispatchCmd gitdir activeBranches =
  simpleCmdArgs (Just version) "Fedora package branch building tool"
    "This tool helps with updating and building package branches" $
    subcommands
    [ Subcommand "clone" "clone packages" $
      cloneCmd <$> optional branchOpt <*> cloneRequest
    , Subcommand "switch" "Switch branch" $
      switchCmd <$> (anyBranchOpt <|> anyBranchArg) <*> many (pkgArg "PACKAGE...")
    , Subcommand "status" "Status package/branch status" $
      statusCmd <$> switchWith 'r' "reviews" "Status of reviewed packages" <*> branchesPackages
    , Subcommand "merge" "Merge from newer branch" $
      mergeCmd <$> branchesPackages
    , Subcommand "build" "Build package(s)" $
      buildCmd <$> mergeOpt <*> optional scratchOpt <*> targetOpt <*> branchesPackages
    , Subcommand "bugs" "List package bugs" $
      bugsCmd <$> optional (pkgArg "PACKAGE")
    , Subcommand "pull" "Git pull packages" $
      pullPkgs <$> some (pkgArg "PACKAGE...")
    , Subcommand "create-review" "Create a Package Review request" $
      createReview <$> noScratchBuild <*> optional (strArg "SPECFILE")
    , Subcommand "update-review" "Update a Package Review" $
      updateReview <$> noScratchBuild <*> optional (strArg "SPECFILE")
    , Subcommand "reviews" "List package reviews" $
      reviewsCmd <$> reviewStatusOpt
    , Subcommand "request-repos" "Request dist git repo for new approved packages" $
      requestRepos <$> many (pkgArg "NEWPACKAGE...")
    , Subcommand "import" "Import new approved created packages from bugzilla review" $
      importCmd <$> many (pkgArg "NEWPACKAGE...")
    , Subcommand "request-branches" "Request branches for approved created packages" $
      requestBranches <$> mockOpt <*> branchesRequestOpt
    , Subcommand "find-review" "Find package review bug" $
      review <$> pkgArg "PACKAGE"
    , Subcommand "test-bz-token" "Check bugzilla login status" $
      pure testBZlogin
    ]
  where
    cloneRequest :: Parser CloneRequest
    cloneRequest = flagWith' (CloneUser Nothing) 'M' "mine" "Your packages" <|> CloneUser . Just <$> strOptionWith 'u' "user" "USER" "Packages of FAS user" <|> ClonePkgs <$> some (pkgArg "PACKAGE...")

    noScratchBuild = switchWith 'n' "no-scratch-build" "Skip Koji scratch build"

    reviewStatusOpt :: Parser ReviewStatus
    reviewStatusOpt =
      flagWith' ReviewUnApproved 'u' "unapproved" "Package reviews not yet approved" <|>
      flagWith' ReviewApproved 'a' "approved" "All open approved package reviews" <|>
      flagWith' ReviewWithoutRepoReq 'w' "without-request" "Approved package reviews without a repo request" <|>
      flagWith' ReviewRepoRequested 'r' "requested" "Approved package reviews with a pending repo request" <|>
      flagWith' ReviewRepoCreated 'c' "created" "Approved package reviews with a created repo" <|>
      flagWith ReviewAllOpen ReviewUnbranched 'b' "unbranched" "Approved created package reviews not yet branched"

    branchOpt :: Parser Branch
    branchOpt = optionWith branchM 'b' "branch" "BRANCH" "branch"

    branchArg :: Parser Branch
    branchArg = argumentWith branchM "BRANCH.."

    branchM :: ReadM Branch
    branchM = eitherReader (eitherActiveBranch activeBranches)

    anyBranchOpt :: Parser Branch
    anyBranchOpt = optionWith anyBranchM 'b' "branch" "BRANCH" "branch"

    anyBranchArg :: Parser Branch
    anyBranchArg = argumentWith anyBranchM "BRANCH.."

    anyBranchM :: ReadM Branch
    anyBranchM = eitherReader eitherBranch

    pkgArg :: String -> Parser Package
    pkgArg lbl = removeSuffix "/" <$> strArg lbl

    pkgOpt :: Parser String
    pkgOpt = removeSuffix "/" <$> strOptionWith 'p' "package" "PKG" "package"

    branchesPackages :: Parser ([Branch],[Package])
    branchesPackages = if gitdir then
      pair <$> (many branchOpt <|> many branchArg) <*> pure []
      else pair <$> many branchOpt <*> many (pkgArg "PACKAGE..") <|>
           pair <$> many branchArg <*> some pkgOpt

    pair a b = (a,b)

    branchesRequestOpt :: Parser BranchesRequest
    branchesRequestOpt = flagWith' AllReleases 'a' "all" "Request branches for all current releases [default latest 2]" <|> BranchesRequest <$> many branchArg

    scratchOpt :: Parser Scratch
    scratchOpt = flagWith' AllArches 's' "scratch" "Koji scratch test build" <|>
                 Arch <$> strOptionWith 'a' "arch" "ARCH[,ARCH].." "Scratch build for arch(s)"

    targetOpt :: Parser (Maybe String)
    targetOpt = optional (strOptionWith 't' "target" "TARGET" "Koji target")

    mergeOpt = switchWith 'm' "merge" "merge from newer branch"

    mockOpt = switchWith 'm' "mock" "Do mock build to test branch"
