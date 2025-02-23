#"
#' Outlier Detection App: Application to identify outliers in time-series data.
#' Author: Mauro Gwerder
#' 
#' In this main file, the input data is processed for feeding it into the modules.
#' 
#' package requirements:

library(shiny)
library(shinydashboard)
library(ggplot2)
library(data.table) 
library(gplots) # for heatmap.2
library(dendextend) # for colouring dendrogram branches
library(RColorBrewer) # colour palettes for heatmap.2
library(gridExtra) # presentation of several plots in a grid
library(imputeTS) # for interpolating NAs

options(shiny.maxRequestSize = 400 * 1024 ^ 2)

server <- function(input, output) {
  
  # clustering and generation of heatmap
  callModule(HierCluster, "HierCluster", in.data = dataInBoth)
  
  # Application of rolling window algorithm and interpolation
  callModule(RollWin, "RollWin", in.data = dataInBoth)
  
  # reactive values used for loading data from two different sources
  # -> see dataInBoth()
  counter <- reactiveValues(
    loadData = isolate(input$b.loaddata),
    synData = isolate(input$b.syndata) 
  )
  
  # column names from loaded data can be selected for column extraction in loadColData()
  output$uiOut.ID <- renderUI({
    cat("output UI ID\n")
    InCols <- getDataCols()
    selectInput(
      "inSelID",
      "Select ID column (e.g. TrackLabel):",
      InCols
    )
  })
  
  output$uiOut.time <- renderUI({
    cat("output UI Time\n")
    InCols <- getDataCols()
    selectInput(
      "inSelTime",
      "Select time column (e.g. MetaData_Time):",
      InCols
    )
  })
  
  output$uiOut.meas1 <- renderUI({
    cat("output UI Meas1\n")
    InCols <- getDataCols()
    selectInput(
      "inSelMeas1",
      "Select first measurement column:",
      InCols
    )
  })
  # optional selection for 2nd measurement column. The necessary operator can be selected in 'output$uiOut.ops'
  output$uiOut.meas2 <- renderUI({
    cat("output UI meas2\n")
    InCols <- getDataCols()
    selectInput(
      "inSelMeas2",
      "Select 2nd Measurement (optional):",
      c("none", InCols)
    )
  })
  
  output$uiOut.ops <- renderUI({
    dm.in <- loadData()
    cat("output UI ops\n")
    # the operator selection will only appear if a 2nd measurement column was chosen
    if(is.null(input$inSelMeas2) || input$inSelMeas2 == "none")
      return(NULL)
    radioButtons(
      "inSelOps",
      "Math operation 1st and 2nd meas.:",
          c(
            "None" = "none",
            "Divide" = " / ",
            "Sum" = " + ",
            "Multiply" = " * ",
            "Subtract" = " - ",
            "1 / X" = "1 / "
          )
    )
  })
  
  output$uiOut.FOV <- renderUI({
    cat("output UI FOV\n")
    InCols <- getDataCols()
    selectInput(
      "inSelFOV",
      "Select FOV column (optional):",
      c("none", InCols)
    )
  })
  
  
  # extracts data of chosen columns out of loaded dataset
  # gives universal column names
  loadColData <- eventReactive(input$b.loaddata, {
    
    cat("extracting Data from selected column\n")
    dm.in <- loadData()
    
    if(is.null(dm.in))
      return(NULL)
    dm.DT <- as.data.table(dm.in)
    dm.DT[, ID := get(input$inSelID)]
    dm.DT[, TIME := get(input$inSelTime)]
    
    if(input$inSelMeas2 == "none" || input$inSelOps == "none")
      loc.meas = input$inSelMeas1
    else if (input$inSelOps == "1 / ")
        loc.meas = paste0(input$inSelOps, input$inSelMeas1)
    else 
        # pastes the two measurement column names and the operator together to one string
        loc.meas = paste0(input$inSelMeas1, input$inSelOps, input$inSelMeas2)
    
    dm.DT[, MEAS := eval(parse(text = loc.meas))]
    
    if(input$inSelFOV == "none")
      dm.DT[, FOV := "-"]
    else
      dm.DT[, FOV := get(input$inSelFOV)]
    
    dm.out <- dm.DT[, .(ID, TIME, MEAS, FOV)]
    return(dm.out)
  })
  
  # extracts column names from loaded data set
  getDataCols <- reactive({
    
    cat("getting the Data columns\n")
    dm.in <- loadData()
    dm.out<- colnames(dm.in)
    return(dm.out)
    
  })
  
  # converts column names of the synthetic generated dataset to universal column names
  # this increases readability inside the modules
  synColData <- reactive({
    
    cat("extracting synthetic data\n")
    dm.in <- synData()
    
    if(is.null(dm.in))
      return(NULL)
    
    dm.in[, ID := TrackLabel]
    dm.in[, TIME := Metadata_RealTime]
    dm.in[, MEAS := objCyto_Intensity_MeanIntensity_imErkCor]
    dm.in[, FOV := Metadata_Site]
    dm.out <- dm.in[, .(ID, TIME, MEAS, FOV)]
    
    if(input$check.super) {
      dm.out <- dm.out[c(320:330), MEAS := 10]
      dm.out <- dm.out[c(1400:1410), MEAS := 10]
    }
    
    return(dm.out)
    
  })
  
  # generates synthetic dataset. 
  # Function "LOCgenTraj" taken from Maciej Dobrzynski from his application "Timecourse inspector"
  synData <- eventReactive(input$b.syndata, {
    
    cat("creating SYNTHETIC DATA\n")
    dm <- LOCgenTraj(in.addout = input$slider.syn)
    
    return(dm)
  })
  
  # loads Data file 
  loadData <- eventReactive(input$file.name, {
    dm <- input$file.name
    cat("DataLoad\n")
    if (!(is.null(dm) || dm == ""))
      return(fread(dm$datapath))
  })
  
  # manages which source (synthetic data of loaded data) will be transmitted to the modules.
  # To enable this, button clicks will be registered so that only the last click decides on
  # which source is piloted.
  dataInBoth <- reactive({
    
    InLoadData <- input$b.loaddata
    InSynData <- input$b.syndata
    
    cat("\n1.0: ",
        InLoadData,
        "\n1.1: ",
        isolate(counter$loadData),
        "\n2.0: ",
        InSynData,
        "\n2.1: ",
        isolate(counter$synData),
        "\n")
    
    # isolate the checks of counter reactiveValues
    # as we set the values in this same reactive
    if (InLoadData != isolate(counter$loadData)) {
      cat("dataInBoth if InLoadData\n")
      dm = loadColData()
      
      counter$loadData <- InLoadData
      
    } else if (InSynData != isolate(counter$synData)) {
      cat("dataInBoth if InSynData\n")
      dm = synColData()
      
      counter$synData <- InSynData
      
    } else {
      cat("dataInBoth else\n")
      dm = NULL
    }
    return(dm)
  })
  
}

