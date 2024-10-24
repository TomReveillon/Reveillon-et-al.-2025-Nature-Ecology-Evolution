setwd("~/LIMNO 2019-2023/Experiments/Predator Ingestion Beads")

rm(list=ls())

library(bbmle)
library(cowplot)
library(data.table)
library(deSolve)
library(directlabels)
library(dplyr)
library(dynlm)
library(foreach)
library(ggplot2)
library(ggrepel)
library(grid)
library(gridExtra)
library(lme4)
library(lmtest)
library(magrittr)
library(nlme)
library(plotly)
library(plyr)
library(propagate)
library(reshape2)
library(scales)

###################################################################################
###################################################################################
##### FUNCTIONAL RESPONSE FOR PREDATOR-PREY SYSTEM WITH DIFFERENT CLONE TYPES #####
###################################################################################
###################################################################################

# Import the dataset
DataI=read.table("Data_FRBI.txt", h=T, dec=",")
names(DataI)
summary(DataI)

# Specify the variables as numeric or factor
DataI[,c(3,8)] %<>% mutate_if(is.numeric,as.character())
DataI[,c(4:7,9)] %<>% mutate_if(is.character,as.numeric)

# Preserve the order of factors
DataI$Bead=factor(DataI$Bead, levels=unique(DataI$Bead))

# Calculate the initial densities
DataI$IDens=round(DataI$Cells*DataI$Volu*DataI$Site*DataI$Dilu*DataI$Cove,0)
DataI=ddply(DataI,.(Strain,Conc,Bead), summarize, IDens=round(mean(IDens),0))

# Import the dataset
DataF=read.table("Data_FRBF.txt", h=T, dec=",")
names(DataF)
summary(DataF)

# Specify the variables as numeric numbers
DataF[,c(3,8)] %<>% mutate_if(is.numeric,as.character())
DataF[,c(4:7,9)] %<>% mutate_if(is.character,as.numeric)

# Preserve the order of factors
DataF$Bead=factor(DataF$Bead, levels=unique(DataF$Bead))

# Calculate the final densities
DataF$FDens=round(DataF$Cells*DataF$Volu*DataF$Site*DataF$Dilu*DataF$Cove,0)
DataF=ddply(DataF,.(Strain,Conc,Bead,Trial), summarize, FDens=round(mean(FDens),0))

# Create a complete dataset
Data=data.frame(Strain=DataF[,1], Conc=DataF[,2], Bead=DataF[,3], Trial=DataF[,4], Time=rep(8/24,432), Pred=rep(4,432), IDens=rep(DataI[,4], each=3), FDens=DataF[,5])

# Calculate densities depletion
Data$DDens=(Data$IDens-Data$FDens)
Data$DDens[Data$DDens<0]=0

# Convert density into ingestion rate
Data$Inges=Data$DDens/Data$Time

# Calculate ingestion rate per rotifer
Data$Inges=Data$Inges/4

# Correct ingestion rate per volume
Data$Inges=Data$Inges/5

# Replace negative values by 0 values
Data$Inges=round(Data$Inges,4)
Data$Inges[Data$Inges<0]=0
Data[is.na(Data)]=0


#######################################
### Ordinary differential equations ###
#######################################

# Rescale densities
Data[,c(7:10)]=Data[,c(7:10)]/10^5

# Calculate particle densities
DensB=rep(NA,length(Data[,1]))
for (i in 1:length(Data[,1])) {
  if (Data[i,3]=="C") Data$DensB[i]=Data[i,2]*0.000
  if (Data[i,3]=="L") Data$DensB[i]=Data[i,2]*0.063
  if (Data[i,3]=="M") Data$DensB[i]=Data[i,2]*0.125
  if (Data[i,3]=="H") Data$DensB[i]=Data[i,2]*0.250
}

# Split the dataset
SplitData=split(Data, list(Data$Strain))
SplitData=SplitData[sapply(SplitData, function(x) dim(x)[1]) > 0]

# Extract combinations of names
Strain=lapply(SplitData, function(x) {unique(x$Strain)})
Strain=as.character(unlist(Strain))
Param=unique(c("a","h","c","sigma"))

# Functional response function
Inges=function(t, x, parms){
  with(as.list(parms),{
    dA = (-a*x[1]/(1 + a*h*x[1] + c*DensB))*P
    return(list(c(dA)))
  })
}

# Densities depletion function
DDensA=c()
DensEaten=function(IDens, a, h, c, DensB, P, Time, steps=100) {
  for (i in 1:length(IDens)){
    DDensA[i] = IDens[i] - lsoda(y=IDens[i], times=seq(0,Time[i],length=steps), func=Inges, parms=c(a=a, h=h, c=c, DensB=DensB[i], P=P[i]))[100,2]
  }
  return(DDensA)
}

# Maximum likelihood function
Likelihood=function(DDens, IDens, a, h, c, sigma, DensB, P, Time, steps=100){
  if(a <= 0 || h <= 0 || c <= 0 || sigma <= 0) return(Inf)
  Func=DensEaten(IDens=IDens, a=a, h=h, c=c, DensB=DensB, P=P, Time=Time, steps=steps)
  LR=-1*sum(dnorm(x=log(DDens+1), mean=log(Func+1), sd=sigma, log=T))
  return(LR)
}

# Fitting the model
FuncHII=function(x) {
  ModHII=mle2(Likelihood, start=list(a=0.1, h=5, c=5, sigma=1), control=list(maxit=1000), data=list(IDens=x$IDens, DDens=x$DDens, DensB=x$DensB, P=x$Pred, Time=x$Time))}
OutHII=lapply(SplitData[c(1:6)], FuncHII)

CoefHII=lapply(OutHII, summary)
CoefHII=lapply(CoefHII, coef)
CoefHII=round(as.data.frame(do.call("rbind",CoefHII)),4)
CoefHII=cbind(Strain=rep(Strain[c(1:6)], each=4),Param=rep(Param,6),Value=CoefHII[,c(1)],Error=CoefHII[,c(2)])
CoefHII=as.data.frame(CoefHII)
rownames(CoefHII)=c()

# Fitting the model
FuncHII=function(x) {
  ModHII=mle2(Likelihood, start=list(a=0.1, h=5, c=5, sigma=1), control=list(maxit=1000), data=list(IDens=x$IDens, DDens=x$DDens, DensB=x$DensB, P=x$Pred, Time=x$Time))}
OutHII=lapply(list(Data), FuncHII)

# Specify the variables as numeric or factor
CoefHII[,c(3:4)] %<>% mutate_if(is.character,as.numeric)

# Create a dataset
Data2=data.frame(Strain=CoefHII[,1], Coeff=CoefHII[,3], CoeffLSD=CoefHII[,3]-CoefHII[,4], CoeffUSD=CoefHII[,3]+CoefHII[,4])
Data2[,c(2:4)]=round(Data2[,c(2:4)],4)
Data2[,c(2:4)][Data2[,c(2:4)]<0]=0
Data2=Data2[c(3,7,11,15,19,23),]


###########################################
### Plotting predicted bed coefficients ###
###########################################

tiff('Microplastic Coefficient Beads.tiff', units="in", width=8, height=8, res=1000)
ggplot(Data2, aes(Strain, Coeff, group=Strain)) +
  geom_point(aes(color=Strain), size=5, pch=16) +
  geom_errorbar(aes(Strain, Coeff, ymin=CoeffLSD, ymax=CoeffUSD, color=Strain), linetype="solid", alpha=0.7, size=1.2, width=0.2) +
  ylab(expression(italic('B. calyciflorus')~'microplastic coefficient')) +
  xlab(expression(italic('C. reinhardtii')~'strain')) +
  theme(axis.text.y=element_text(face="plain", colour="black", size=18)) +  
  theme(axis.text.x=element_text(face="plain", colour="black", size=18)) + 
  theme(axis.title.y=element_text(face="plain", colour="black", size=18)) +
  theme(axis.title.x=element_text(face="plain", colour="black", size=18)) +
  scale_y_continuous(labels=function(x) sprintf("%.0f", x), breaks=seq(0,120,by=30), limits=c(0,120)) +
  scale_x_discrete(labels=c("CR1"=expression(C[R1]),"CR2"=expression(C[R2]),"CR3"=expression(C[R3]),"CR4"=expression(C[R4]),"CR5"=expression(C[R5]),"CR6"=expression(C[R6]))) +
  theme(axis.line=element_line(colour="black")) + theme(panel.background=element_blank()) +
  theme(panel.grid.major=element_blank(), panel.grid.minor=element_blank()) +
  scale_color_manual(values=c("CR1"="mediumpurple3","CR2"="steelblue2","CR3"="chartreuse3","CR4"="gold2","CR5"="darkorange1","CR6"="tomato2")) +
  theme(legend.position="none")
dev.off()
