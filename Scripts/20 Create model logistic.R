require("geneorama")
geneorama::detach_nonstandard_packages()
require("geneorama")
require("data.table")
require("ROCR")
require("caret")

fulldat <- readRDS("Data/Model data.RDS")

# #Remove ID vars from data
# fulldat$id <- NULL
# fulldat$Inspection_Date <- NULL
# fulldat$Inspection_ID <- NULL


#Calculate a correlation matrix
# cors <- cor(dat)
# write.table(cors, "Temp/Correlation matrix.csv", quote = FALSE, sep = ",", row.names = TRUE)

##########################################
#Create test and train data
##########################################
fulldat$fail_flag <- as.factor(fulldat$fail_flag)

#Set aside two months of data for testing
twomonth_sample <- fulldat[Inspection_Date >= as.IDate("2015-09-01") & Inspection_Date < as.IDate("2015-11-01")]

#Create regular test and train samples
dat <- fulldat[Inspection_Date >= as.IDate("2013-10-01") & Inspection_Date < as.IDate("2015-09-01")]

#Calculate train data size
smp_size <- floor(0.75 * nrow(dat))

## set the seed to make partition reproductible
set.seed(123)

##Partition data
train_ind <- sample(seq_len(nrow(dat)), size = smp_size)

train <- dat[train_ind, ]
test <- dat[-train_ind, ]


##########################################
#Implement stepwise selection
##########################################

#Create list of vars to include in model
allvars <- list("otherviol_heat", "past_fail", "timeSinceLast", "category_restaurant", "category_takeout", "category_market", "category_school", "firstRecord", "burglary_heat", "larceny_heat", "vandalism_heat", "drug_heat", "noise_heat", "airpol_heat", "rodent_heat", "trash_heat", "d311_heat", "construct_heat", "demolish_heat", "dumping_heat30", "waterpol_heat30", "temp", "humid", "precip", "temp3day_avg", "humid3day_avg", "precip3day_sum", "liquor_license", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "CitySilverSpring", "CityRockville", "CityGaithesburg", "CityBethesda", "CityGermantown", "CityOlney", "CityWheaton")

#Define the full model formula
fullmod_formula <- paste("fail_flag ~ ", paste(allvars, collapse= "+"))

#Define the null hypothesis formula
nothing_formula <- "fail_flag ~ 1"

#Fit both models
fullmod <- glm(fullmod_formula,family=binomial(link='logit'),data=train)
nothing <- glm(nothing_formula,family=binomial(link='logit'),data=train)

#Perform stepwise logistic regression
bothways = step(nothing, list(lower=formula(nothing),upper=formula(fullmod)), direction="both")
summary(bothways)

#Plot ROC curve 
pred_values <- predict(bothways, type="response", new=test)
pred <- prediction(pred_values, test$fail_flag)
rocperf = performance(pred, measure = "tpr", x.measure = "fpr")
plot(rocperf)
abline(a=0, b= 1)

#Find the AUC
slot(performance(pred, "auc"), "y.values")[[1]]

#Generate a lift chart
liftperf <- performance(pred, measure="lift", x.measure="rpp")
plot(liftperf)
abline(a=1, b=0)
abline(a=1.2, b=0)
abline(a=1.4, b=0)

#Show confusion matrix
predict_bothways_train <- as.factor(ifelse(predict(bothways, type="response", new=test)>=0.5,1, 0))
confusionMatrix(predict_bothways_train, test$fail_flag, positive="1")

#Show confusion matrix - different threshold
predict_bothways_train <- as.factor(ifelse(predict(bothways, type="response", new=test)>=0.3,1, 0))
confusionMatrix(predict_bothways_train, test$fail_flag, positive="1")

#############=========================================================================
#Test results on the two-month sample
twomonth_sample$prob_violation <- predict(bothways, type="response", new=twomonth_sample)

#Calculate share of violations found in the first month of test
count_v_actual_all <- nrow(subset(twomonth_sample, (fail_flag==1)))
count_v_actual_sep <- nrow(subset(twomonth_sample, (fail_flag==1) & (Inspection_Date <= as.IDate("2015-10-01"))))
share_v_actual_sep <- count_v_actual_sep/count_v_actual_all

#Calculate share of violations that could have been found in first month of test (assumes that time-variable trends stay constant)
#how many inspections were done in September
count_actual_sep <- nrow(subset(twomonth_sample, Inspection_Date <= as.IDate("2015-10-01")))

#how they would have been structured according to the model
twomonth_sample <- twomonth_sample[order(-rank(prob_violation))]

write.table(twomonth_sample, "Temp/twomonth.csv", quote = FALSE, sep = ",", row.names = FALSE)

#what share would have actually been found
twomonth_sample_sep <- head(twomonth_sample, count_actual_sep)
count_v_est_sep <- nrow(subset(twomonth_sample_sep, fail_flag==1))
share_v_est_sept <- count_v_est_sep/count_v_actual_all
improv <- share_v_est_sept-share_v_actual_sep

print(paste("Overall improvement in share found:", improv, "- from", share_v_actual_sep, "to", share_v_est_sept))
print(paste("Overall improvement in number found:", count_v_actual_sep, "violations were found, but", count_v_est_sep, "could have been found. That's", count_v_est_sep-count_v_actual_sep, "in a month."))

#######Calculate number of days improvement
#Number of inspections per day
daily_insp <- round(nrow(twomonth_sample)/61)

#Day number when violation would have been found
twomonth_sample$day_estimated <- rep(seq(1,61), each=20)[1:nrow(twomonth_sample)]

#Day number when violation was found
library("lubridate")
twomonth_sample$day_found <- yday(twomonth_sample$Inspection_Date) - yday(min(twomonth_sample$Inspection_Date))

#Calculate the difference
avg_day_gain <- mean(twomonth_sample$day_found-twomonth_sample$day_estimated)

print(paste("Average number of days gained was", avg_day_gain))
