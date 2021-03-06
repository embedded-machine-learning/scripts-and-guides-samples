#!/bin/bash

###
# Functions
###

setup_env()
{
  # Environment preparation
  echo Activate environment $PYTHONENV
  #call conda activate %PYTHONENV%
  #Environment is put directly in the nuc home folder
  . ~/tf2odapi/init_eda_env.sh
}

get_model_name()
{
  MYFILENAME=`basename "$0"`
  MODELNAME=`echo $MYFILENAME | sed 's/openvino_inf_eval_saved_model_//' | sed 's/.sh//'`
  echo Selected model based on folder name: $MODELNAME
}

get_width_and_height()
{
  elements=(${MODELNAME//_/ })
  #$(echo $MODELNAME | tr "_" "\n")
  #echo $elements
  resolution=${elements[2]}
  res_split=(${resolution//x/ })
  height=${res_split[0]}
  width=${res_split[1]}

  echo batch processing height=$height and width=$width

}

infer()
{
  echo Apply to model $MODELNAME with type $HARDWARETYPE

  echo #====================================#
  echo # Infer with OpenVino
  echo #====================================#
  echo "Start latency inference"
  python $SCRIPTPREFIX/hardwaremodules/openvino/run_pb_bench_sizes.py \
  -openvino_path $OPENVINOINSTALLDIR \
  -hw $HARDWARETYPE \
  -batch_size 1 \
  -api $APIMODE \
  -niter 1000 \
  -xml "exported-models-openvino/$MODELNAME/saved_model.xml" \
  -output_dir="results/$MODELNAME/$HARDWARENAME/openvino"

  #::-size [1,320,320,3] ^
  #::-hw (CPU|MYRIAD)
  #::-size (batch, width, height, channels=3)
  #::-pb Frozen file

  echo #====================================#
  echo # Convert Latencies
  echo #====================================#
  echo "Add measured latencies to result table"
  python3 $SCRIPTPREFIX/hardwaremodules/openvino/openvino_latency_parser.py \
  --avg_rep results/$MODELNAME/$HARDWARENAME/openvino/benchmark_average_counters_report_$HARDWARETYPE\_$APIMODE.csv \
  --inf_rep results/$MODELNAME/$HARDWARENAME/openvino/benchmark_report_$HARDWARETYPE\_$APIMODE.csv \
  --output_path results/latency_$HARDWARENAME.csv \
  --hardware_name $HARDWARENAME
  #::--save_new #Always append

  echo #====================================#
  echo # Infer with OpenVino
  echo #====================================#
  echo "Start accuracy/performance inference"
  python3 $SCRIPTPREFIX/hardwaremodules/openvino/test_write_results.py \
  --model_path="exported-models-openvino/$MODELNAME/saved_model.xml" \
  --image_dir="images/validation" \
  --device=$HARDWARETYPE \
  --detections_out="results/$MODELNAME/$HARDWARENAME/detections.csv"


  echo #====================================#
  echo # Convert to Pycoco Tools JSON Format
  echo #====================================#
  echo "Convert TF CSV to Pycoco Tools csv"
  python $SCRIPTPREFIX/conversion/convert_tfcsv_to_pycocodetections.py \
  --annotation_file="results/$MODELNAME/$HARDWARENAME/detections.csv" \
  --output_file="results/$MODELNAME/$HARDWARENAME/coco_detections.json"

  echo #====================================#
  echo # Evaluate with Coco Metrics
  echo #====================================#

  python $SCRIPTPREFIX/inference_evaluation/objdet_pycoco_evaluation.py \
  --groundtruth_file="annotations/coco_pets_validation_annotations.json" \
  --detection_file="results/$MODELNAME/$HARDWARENAME/coco_detections.json" \
  --output_file="results/performance_$HARDWARENAME.csv" \
  --model_name=$MODELNAME \
  --hardware_name=$HARDWARENAME\_$HARDWARETYPE
}


###
# Main body of script starts here
###

echo #==============================================#
echo # CDLEML Process TF2 Object Detection API for OpenVino
echo #==============================================#

# Constant Definition
#USEREMAIL=alexander.wendt@tuwien.ac.at
#MODELNAME=tf2oda_efficientdet_512x384_pedestrian_D0_LR02
#MODELNAME=tf2oda_ssdmobilenetv2_300x300_pets_D100_OVFP16
PYTHONENV=tf24
#BASEPATH=`pwd`
SCRIPTPREFIX=../../scripts-and-guides/scripts
HARDWARENAME=IntelNUC
LABELMAP=label_map.pbtxt

#Openvino installation directory for the inferrer (not necessary the same as the model optimizer)
OPENVINOINSTALLDIR=/opt/intel/openvino_2021
APIMODE=sync
HARDWARETYPELIST="CPU GPU MYRIAD"
#HARDWARETYPELIST="CPU"

echo Extract model name from this filename
get_model_name

echo Extract height and width from model
get_width_and_height

echo Setup environment
setup_env

#echo "Start training of $MODELNAME on EDA02" | mail -s "Start training of $MODELNAME" $USEREMAIL

echo "Setup task spooler socket."
. ~/tf2odapi/init_eda_ts.sh

echo "Setup Openvino environment and variables"
source /opt/intel/openvino_2021/bin/setupvars.sh

alias python=python3

for HARDWARETYPE in $HARDWARETYPELIST
do
  #echo "$f"
  #MODELNAME=`basename ${f%%.*}`
  echo $HARDWARETYPE
  infer
  
done

