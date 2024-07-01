#R                                                                                                                                                            
                                                                                                                                                              
library(testthat)                                                                                                                                             
                                                                                                                                                              
suppressPackageStartupMessages(library(rawDiag))                                                                                                                

rawDiag::checkRawrr()

if (isFALSE(rawrr::.checkDllInMonoPath())){
  rawrr::installRawFileReaderDLLs()
}
rawrr::installRawrrExe()
                                                                                                                                                              
test_check("rawDiag")   
