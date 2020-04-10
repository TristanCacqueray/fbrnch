module Cmd.Status (statusCmd) where

import Control.Monad
import Distribution.Fedora.Branch
import SimpleCmd
import System.Directory
import System.FilePath

import Bugzilla
import Branches
import Git
import Koji
import ListReviews
import Package
import Types (Package)

-- FIXME add --no-pull?
-- FIXME --pending
statusCmd :: Maybe Branch -> [Package] -> IO ()
statusCmd mbr ps = do
  pkgs <- if null ps
    then map reviewBugToPackage <$> listReviews' True ReviewRepoCreated
    else return ps
  mapM_ (statusPkg mbr) pkgs

statusPkg :: Maybe Branch -> Package -> IO ()
statusPkg mbr pkg =
  withExistingDirectory pkg $ do
    putPkgHdr pkg
    git_ "fetch" []
    branches <- case mbr of
                  Just b -> return [b]
                  Nothing -> packageBranches
    mapM_ (statusBranch (Just pkg)) branches

statusBranch :: Maybe Package -> Branch -> IO ()
statusBranch mpkg br = do
  pkg <- getPackageName mpkg
  branched <- gitBool "show-ref" ["--verify", "--quiet", "refs/remotes/origin/" ++ show br]
  if not branched
    then putStrLn $ "No " ++ show br ++ " branch"
    else do
    clean <- workingDirClean
    if not clean then
      putStrLn "working dir is dirty"
      else do
      switchBranch br
      let spec = pkg <.> "spec"
      haveSpec <- doesFileExist spec
      if not haveSpec then do
        newrepo <- initialPkgRepo
        if newrepo then putStrLn $ show br ++ ": initial repo"
          else putStrLn $ "missing " ++ spec
        else do
        mnvr <- cmdMaybe "fedpkg" ["verrel"]
        case mnvr of
          Nothing -> do
            putStrLn "undefined NVR!\n"
            putStr "HEAD "
            simplifyCommitLog <$> gitShortLog1 Nothing >>= putStrLn
          Just nvr -> do
            unless (br == Master) $ do
              prev <- do
                branches <- getFedoraBranches
                return $ newerBranch branches br
              ancestor <- gitBool "merge-base" ["--is-ancestor", "HEAD", show prev]
              when ancestor $ do
                unmerged <- gitShortLog $ "HEAD.." ++ show prev
                unless (null unmerged) $ do
                  putStrLn $ "Newer commits in " ++ show prev ++ ":"
                  mapM_ (putStrLn . simplifyCommitLog) unmerged
            unpushed <- gitShortLog1 $ Just $ "origin/" ++ show br ++ "..HEAD"
            if null unpushed then do
              tagged <- kojiBuildTagged nvr
              unless tagged $ do
                latest <- cmd "koji" ["latest-build", "--quiet", branchDestTag br, pkg]
                putStrLn $ if dropExtension nvr == dropExtension latest then nvr ++ " is already latest" else (if null latest then "new " else latest ++ " ->\n") ++ nvr
              else putStrLn $ show br ++ ": " ++ simplifyCommitLog unpushed