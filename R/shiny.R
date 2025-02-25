#R

#' @noRd
#' @importFrom shiny fluidPage titlePanel sidebarLayout sidebarPanel mainPanel downloadButton downloadHandler
.buildRawDiagServer <- function(input, output, session) {

    vals <- reactiveValues(rawfile  = NA, gp = NULL, pdfFileName = NULL,
                           plot = NULL, generatePDF = 0)

    observeEvent(input$rawfile, {
        vals$rawfile = input$rawfile;
        message(vals$rawfile )
    })

    observeEvent(input$generatePDF, {
        vals$generatePDF <- vals$generatePDF + 1
    })
    rawDiag::rawDiagServer("OrbitrapFun02", vals)

    output$downloadPdf <- downloadHandler(
        filename = function() {
            basename(vals$pdfFileName)
        },
        content = function(file) {
            file.copy(
                from = vals$pdfFileName,
                to = file
            )
        }
    )
}

#' @noRd
#' @importFrom shiny fluidPage titlePanel sidebarLayout sidebarPanel mainPanel downloadButton downloadHandler actionButton
.buildRawDiagUI <- function(files){
  ## Define UI for application that draws a histogram
  fluidPage(
    ## Application title
    titlePanel("rawDiag - Brings Orbitrap Mass Spectrometry Data to Life; Fast and Colorful"),

    ## Sidebar with a slider input for number of bins
    sidebarLayout(
      sidebarPanel(
        tagList(
          # html::img(src='https://github.com/cpanse/rawDiag/blob/main/vignettes/octopussy.png', height = 100),
          selectInput("rawfile", "rawfile",
                      choices = files,
                      selected = files[1], width = "100%", multiple = TRUE),
          actionButton('generatePDF', 'generatePDF'),
          downloadButton("downloadPdf", "Download")
        )
      ),
      mainPanel(
        rawDiag::rawDiagUI("OrbitrapFun02")
      )
    )
  )
}

#' Build the rawDiag shiny application
#'
#' @param rawDir A directory containing the input raw files,
#' default is set to the \code{$HOME/Downloads} directory.
#' @importFrom shiny runApp
#' @import shiny
#' @return returns the rawDiag shiny apps
#' @inherit plotLockMassCorrection author references
#' @export
#'
#' @examplesIf interactive()
#' rawrr::sampleFilePath() |>
#'   dirname() |>
#'   rawDiag::buildRawDiagShinyApp() |>
#'   shiny::runApp()
#'   
#'  # or use your 'Download' folder
#'  (Sys.getenv('HOME') |>
#'    file.path("Downloads")) |>
#'    rawDiag::buildRawDiagShinyApp() |>
#'    shiny::runApp()
#'
#' @note launch the shiny application by embracing your command line while
#' expecting the raw file in \code{$HOME/Downloads}
#' * MacOSX and Linux: `R -q -e "library(rawDiag); buildRawDiagShinyApp() |> shiny::runApp(launch.browser = TRUE)"`
#' * Microsoft Windows: `R.exe -e "library(rawDiag); buildRawDiagShinyApp() |> shiny::runApp(launch.browser = TRUE)"`
#' @md
buildRawDiagShinyApp <- function(rawDir = (rawrr::sampleFilePath() |> dirname())){

  rawDir |>
    file.path(rawDir |>
                list.files(recursive = TRUE,
                           pattern = "*.raw$")) -> files
  
  if (length(files) == 0){
    warning("No raw files found in ", rawDir, " using raw file",
            rawrr::sampleFilePath())
    rawrr::sampleFilePath() -> files
  }

  vapply(files, FUN = file.mtime, FUN.VALUE = 1702718537) |>
    order() -> idx
  files[rev(idx)] -> files

  shiny::shinyApp(ui = .buildRawDiagUI(files), server = .buildRawDiagServer)
}

#' rawDiag shiny module UI
#' @return a shiny UI module
#' @inheritParams shiny::moduleServer
#' @returns rawDiag shiny module UI
#' @importFrom shiny fluidRow column
#' @importFrom htmltools a img
#' @examplesIf interactive()
#' rawDiag::shiny(rawDir = (rawrr::sampleFilePath() |> dirname()))
#' @export
rawDiagUI <- function(id){
  ns <- NS(id)
  
  plotFunctions <- ls("package:rawDiag")[ls("package:rawDiag") |> grepl(pattern = "^plot")]
  
  tagList(
    column(12, offset = 0,
           #fluidRow(a(img(src="https://img.shields.io/badge/JPR-10.1021%2Facs.jproteome.8b00173-brightgreen"),
           #           href='http://dx.doi.org/10.1021/acs.jproteome.8b00173')),
           fluidRow(
             column(width = 4,
                    selectInput(ns("plotFUN"), "function", choices = plotFunctions,
                                selected = plotFunctions[1], multiple = FALSE)),
             column(width = 4,
                    selectInput(ns("plotArg"), "argument", choices = c("trellis", "violin", "overlay"),
                                selected = "trellis", multiple = FALSE),
             ),
             column(width = 3,
                    # checkboxInput(ns('useParallel'), 'Use parallel processing (mclapply)', value = TRUE)
                    ## TODO(cpanse)
                    # checkboxInput(ns('readFileHeader'), 'readFileHeader (rawrr)', value = FALSE)
             )),
           fluidRow(
             column(width = 4,
                    selectInput(ns("plotHeight"), "height x n", choices = seq_len(10),
                                selected = 1, multiple = FALSE)),
             column(width = 4,
                    selectInput(ns("plotWidth"), "width x n", choices = seq_len(4),
                                selected = 1, multiple = FALSE),
             )),
           fluidRow(
             plotOutput(ns("plot"), width = "100%")
           ),
    ))
}

#' rawDiag shiny module
#'
#' @inheritParams shiny::moduleServer
#' @param vals containing rawfile
#' @return rawDiag shiny module server
#' @importFrom shiny moduleServer reactive reactiveValues observeEvent renderPlot req NS tagList selectInput checkboxInput plotOutput debounce
#' @importFrom utils packageVersion
#' @importFrom BiocParallel bplapply
#' @importFrom htmltools a img div
#' @examplesIf interactive()
#' shiny::shiny(rawDir = (rawrr::sampleFilePath() |> dirname()))
#' @export
rawDiagServer <- function(id, vals){
  moduleServer(id,
               function(input, output, session) {
                 rawfile <- reactive({ vals$rawfile }) |>
                   debounce(500)
                 
                 data <- reactive({
                   shiny::req(rawfile())
                   progress <- shiny::Progress$new(session = session)
                   progress$set(message = "Reading Index ...")
                   on.exit(progress$close())
                   vals$pdfFileName <- NULL
                   ## TODO(cp): think about as.rawDiag to ensure all columns are there.
                   
                   BiocParallel::bplapply(rawfile(), function(f){
                     rawDiag::readRaw(f,
                                      msgFUN = function(msg){
                                        progress$set(detail = paste0("from file ", basename(f)),
                                                     message = msg)
                                      })
                   }) |>
                     Reduce(f = rbind)
                   
                 })
                 
                 
                 observeEvent(input$plotFUN, {
                   vals$plot <- input$plotFUN;
                   message(input$plotFUN)
                 })
                 
                 
                 dynamicHeight <- reactive({
                   n <- 400
                   if (input$plotArg == "trellis"){
                     n <- n * length(rawfile()) 
                   }
                   
                   n * as.integer(input$plotHeight)
                 })
                 
                 dynamicWidth <- reactive({
                   n <- 400
                   if (input$plotArg == "trellis"){
                     400 
                   }
                   n * as.integer(input$plotWidth)
                 })
                 
                 output$plot <- renderPlot({
                   shiny::req(data())

                   progress <- shiny::Progress$new(session = session)
                   progress$set(message = "plotting ...")
                   on.exit(progress$close())
                   
                   ## call the plot method
                   do.call(what = input$plotFUN,
                           args = list(x = data(),
                                       method = input$plotArg)) -> gp
                   vals$gp <- gp
                   gp
                 },
                 height = function()dynamicHeight())
                 
                 observeEvent(vals$generatePDF, {
                   shiny::req(data())
                   pdfFileName <- tempdir() |>
                     file.path(paste0("rawDiag",
                                      format(Sys.time(), "_%Y%m%d-%H%M%S_"),
                                      vals$plot, '.pdf'))
                   
                   msg <- paste0("ggplot2::ggsave to file ", pdfFileName)
                   progress <- shiny::Progress$new(session = session, min = 0, max = 1)
                   progress$set(message = msg)
                   on.exit(progress$close())
                   
                   gglabs <- ggplot2::labs(
                     caption = paste0("Generated on ", 
                                      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                      ", @", Sys.info()["nodename"],
                                      " using the rawrr/rawDiag R package versions ", 
                                      packageVersion('rawrr'), "/",
                                      packageVersion('rawDiag'), " ",
                                      R.Version()['version.string'],
                                      ". If you want to cite rawrr and rawDiag in your work, use:\n",
                                      "T. Kockmann and C. Panse (2021), Journal of Proteome Research doi: 10.1021/acs.jproteome.0c00866; ",
                                      "C. Trachsel et al. (2018), Journal of Proteome Research doi: 10.1021/acs.jproteome.8b00173"))
                   
                   rvgg <- ggplot2::ggsave(
                     vals$gp + gglabs,
                     filename = pdfFileName,
                     dpi = 600,
                     device = "pdf",
                     width = 297 * as.integer(input$plotWidth),
                     height = 210 * as.integer(input$plotHeight),
                     units = 'mm',
                     limitsize = FALSE)
                   
                   if (file.exists(pdfFileName)){
                     vals$pdfFileName <- pdfFileName
                   } else{
                     vals$pdfFileName <- NULL
                   }
                 })
                 
               }
  )
}
