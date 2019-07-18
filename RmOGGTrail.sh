#!/bin/bash
#by raysuen
#v02

if [ -f ~/.bash_profile ];then
	source ~/.bash_profile
fi

ComGgsci=/u01/ggs/ggsci         #指定ggsci的绝对路径
ExtractTrailDir=/u01/ggs/dirdat        #指定trail文件的目录
keepfiles=1                     #指定保留文件的数量
rmlog=/u01/scripts/ray/RmOGGTrail.log    #指定删除脚本的日志，记录删除那些trail文件


##################################################################
#获取所有extract 进程信息
##################################################################
getOGGExtractInfo(){
	${ComGgsci}<<-RAY
		info extract *
	RAY
}

##################################################################
#获取进程信息checkpoint信息
##################################################################
getOGGExtractShowch(){
	${ComGgsci}<<-RAY
		info $1 showch
	RAY
}

##################################################################
#函数：删除投递进程指定保留数量前的trail文件 
##################################################################
deleteExtractfile(){
	echo "################################# delete Extract tail #################################" >> ${rmlog}
	##################################################################
	#按照指定进程名称，删除指定保留数量前的日志
	##################################################################
	arrayExtract=()
	arrayExtractNum=0
	isupdate=0
	for i in `getOGGExtractInfo |  egrep -v "GGSCI|^$" | sed -n '/EXTRACT/,$p' | awk -v dumpfile="" -v mynum=1 '{if($1=="EXTRACT") {dumpfile=$2;mynum=1} else if(($4!="Oracle")&&(mynum==3)){print dumpfile;mynum++}else mynum++}'`  #获取所有的投递进程名称
	do
		#获取指定投递进程的当前读取的checkpoint信息
		extractInfo=`getOGGExtractShowch $i  | sed -n '/Read Checkpoint #1/,/Write Checkpoint #1/p' | grep -A 4 "Current Checkpoint"`  #getOGGExtractShowch $i  | sed -n '/Read Checkpoint #1/,/Write Checkpoint #1/p' | grep -A 4 "Current Checkpoint" | awk -v seqno=0 -v trailname="" '{if($1=="Sequence") {seqno=$3} else if($1$2=="ExtractTrail:") {trailname=$3}}END{for(i=6-length(seqno);i>=1;i--) trailname=trailname"0";print trailname""seqno}'
		#获取投递进程读取的trail文件的文件头
		trailePre=`echo "${extractInfo}" | awk '{if($1$2=="ExtractTrail:") print $3}' | sed 's#\./dirdat#'"${ExtractTrailDir}"'#g'`
		#获取当前指定投递进程正在读取的trail文件的序列号
		traileSeq=`echo "${extractInfo}" | awk '{if($1=="Sequence") print $3}'`
		
		#判断是否为第一次，如果为第一次表示数组内没有存放任何extract进程信息。需要给数组内赋值
		if [ ${arrayExtractNum} -eq 0 ];then
			arrayExtract[${arrayExtractNum}]=$i" "${trailePre}" "${traileSeq}
			arrayExtractNum=$[${arrayExtractNum}+1]
		else
			#循环数组，判断数组内的extract进程读取的trail文件是否和当前的extract进程读取的文件一致。如果一致，比对2个进程读取人间的seq号。如果当前进程读取的seq号比数组内进程读取的seq号小，则把数组内的比对的进程信息替换为当前进程信息。
			for ((n=0;n<${#arrayExtract[@]};n++))
			do
				#判断数组内进程读取的checkpoint文件前置名称是否和当前的进程读取的文件前置名称一样
				if [ "${trailePre}" == `echo ${arrayExtract[${n}]} | awk '{print $2}'` ];then
					#如果2个进程的前置名称一样，则比对checkpoint文件的seq号，把相对seq号小的进程保留在数组内
					if [ ${traileSeq} -le `echo ${arrayExtract[${n}]} | awk '{print $3}'` ];then
						arrayExtract[${n}]=$i" "${trailePre}" "${traileSeq}  #根据数组下标，替换seq小的进程信息
						isupdate=1                #修改变量，表示在数组内替换过内容
						#arrayReplicatNum=$[${arrayReplicatNum}-1]
						break
					fi
					
				fi
			done
			if [ ${isupdate} -eq 0 ];then  #如果数组内没有替换过内容，则把当前进程信息添加到数组内，否则修改变量值为0，表示没有替换过数组内容。
				arrayExtract[${arrayExtractNum}]=$i" "${trailePre}" "${traileSeq}
				arrayExtractNum=$[${arrayExtractNum}+1]
			else
				isupdate=0
			fi
			
		fi
		
		#arrayExtractNum=$[${arrayExtractNum}+1]
		
		
	done

for ((i=0;i<${#arrayExtract[@]};i++))
do
	echo "####################### Extract: `echo "${arrayExtract[${i}]}" | awk '{print $1}'` ########################" >> ${rmlog}
	#获取当前进程的trail文件前置名称
	trailePre=`echo "${arrayExtract[${i}]}" | awk '{print $2}'`
	for j in $(ls `echo "${arrayExtract[${i}]}" | awk '{print $2"*"}'`)   #根据trail文件的前置名称ls
	do
		
		#获取文件的序列号，如果为0号文件，可能没有文件号需要重新复制文件序列号。
		existsfilenum=`echo $j | sed -e 's#'"${trailePre}"'##g'`
		#循环去掉文件前缀后的数字，可能会006302,所以要把前面的00去掉。判断第一个非零的数字的位置
		for((pos=0;pos<${#existsfilenum};pos++))
		do
			if [ ${existsfilenum:$pos:1} -ne 0 ];then
                break
			fi
		done
		varlen=$[ ${#existsfilenum} - ${pos} ]       #获取非零数字到字符串结尾的长度
		existsfilenum=`echo ${existsfilenum:$pos:${varlen}}`    #截取字符串，获取真正的文件的seq号
		if [ -z ${existsfilenum} ];then
			existsfilenum=0
		fi
		#判断当前文件是否小于指定seq号，如果小于则删除文件
		extractProcNum=`echo "${arrayExtract[${i}]}" | awk '{print $3}'`
		if [ $[ ${extractProcNum} - ${keepfiles} ] -gt ${existsfilenum} ];then
			echo $j >> ${rmlog}
			#echo "rm -f ${j}" | bash
		fi
		
	done
	#echo ${arrayExtract[${i}]}
done


#循环判断指定投递进程对应的抽取进程的抽取trail文件


}


##################################################################
#获取所有replicat进程信息
##################################################################
getOGGReplicatInfo(){
	${ComGgsci}<<-RAY
		info replicat *
	RAY
}

##################################################################
#函数：删除复制进程指定保留数量前的trail文件 
##################################################################
deleteReplicatfile(){
	
	arrayReplicat=()
	arrayReplicatNum=0
	isupdate=0

	echo "################################# delete Replicat tail #################################" >> ${rmlog}
	#获取复制进程的名称和正在读取的checkpoint文件名称，以逗号分隔
	for i in `getOGGReplicatInfo | egrep -v "GGSCI|^$" | sed -n '/REPLICAT/,$p' | awk -v rname="" '{if($1=="REPLICAT") {rname=$2;mynum=1}else if(($1$2$3=="LogReadCheckpoint")){print rname","$5}}'`  
	do
		
		#获取当前复制进程的trail文件的前置名称
		replicatFilePre=`echo $i | awk -F ',' '{print $2}' | awk -F '/' -v prefile="" '{for(i=1;i<=NF;i++) {if(i==1){continue} else if(i==NF) {prefile=prefile"/"substr($i,1,2)} else {prefile=prefile"/"$i}}}END{print prefile}' | sed 's#\./dirdat#'"${ExtractTrailDir}"'#g'`
		#获取当前进程正在读取的trail文件的seq号
		#replicatSeq=`echo $i | awk -F ',' '{print $2}' | awk -F ''"${replicatFilePre}"'' '{print $NF}' | sed 's#0##g'`
		replicatSeq=`echo $i | awk -F ',' '{print $2}' | awk -F ''"${replicatFilePre}"'' -v mynum=0 '{for(i=0;i<length($NF);i++) if(substr($NF,i,1)!=0) {mynum=i;break}}END{print substr($NF,mynum)}'`
		#获取当前存在的源端投递过来的trail文件
		
		#判断是否为第一次，如果为第一次表示数组内没有存放任何replicat进程信息。需要给数组内赋值
		if [ ${arrayReplicatNum} -eq 0 ];then
			arrayReplicat[${arrayReplicatNum}]=`echo $i | awk -F ',' '{print $1}'`" "${replicatFilePre}" "${replicatSeq}
			arrayReplicatNum=$[${arrayReplicatNum}+1]
		else
			#循环数组，判断数组内的replicat进程读取的trail文件是否和当前的replicat进程读取的文件一致。如果一致，比对2个进程读取人间的seq号。如果当前进程读取的seq号比数组内进程读取的seq号小，则把数组内的比对的进程信息替换为当前进程信息。
			for ((n=0;n<${#arrayReplicat[@]};n++))
			do
				#判断数组内进程读取的checkpoint文件前置名称是否和当前的进程读取的文件前置名称一样
				if [ "${replicatFilePre}" == `echo ${arrayReplicat[${n}]} | awk '{print $2}'` ];then
					#如果2个进程的前置名称一样，则比对checkpoint文件的seq号，把相对seq号小的进程保留在数组内
					if [ ${replicatSeq} -le `echo ${arrayReplicat[${n}]} | awk '{print $3}'` ];then
						arrayReplicat[${n}]=`echo $i | awk -F ',' '{print $1}'`" "${replicatFilePre}" "${replicatSeq}
						isupdate=1                      #修改变量，表示在数组内替换过内容
						break
					fi
					
				fi
			done
			if [ ${isupdate} -eq 0 ];then
				arrayReplicat[${arrayReplicatNum}]=`echo $i | awk -F ',' '{print $1}'`" "${replicatFilePre}" "${replicatSeq}
				arrayReplicatNum=$[${arrayReplicatNum}+1]
			else
				isupdate=0
			fi
			
		fi
		
		#arrayReplicatNum=$[${arrayReplicatNum}+1]
		
	done
	
	
for ((i=0;i<${#arrayReplicat[@]};i++))
do
	echo "####################### Replicat: $(echo ${arrayReplicat[${i}]} | awk '{print $1}') ########################" >> ${rmlog}

	replicatFilePre=`echo "${arrayReplicat[${i}]}" | awk '{print $2}'`
	for j in $(ls `echo "${arrayReplicat[${i}]}" | awk '{print $2"*"}'`)
	do
		#获取文件的seq号
		existsfilenum=`echo $j | sed -e 's#'"${replicatFilePre}"'##g'`
		#循环去掉文件前缀后的数字，可能会006302,所以要把前面的00去掉。判断第一个非零的数字的位置
		for((pos=0;pos<${#existsfilenum};pos++))
		do
			if [ ${existsfilenum:$pos:1} -ne 0 ];then
                break
			fi
		done
		varlen=$[ ${#existsfilenum} - ${pos} ]       #获取非零数字到字符串结尾的长度
		existsfilenum=`echo ${existsfilenum:$pos:${varlen}}`    #截取字符串，获取真正的文件的seq号
		#如果文件的seq为0，重新复制seq为0
		if [ -z ${existsfilenum} ];then
			existsfilenum=0
		fi
		#判断当前的trail文件是否小于保留时间的条件
		replicatProcNum=`echo "${arrayReplicat[${i}]}" | awk '{print $3}'`
		if [ $[ ${replicatProcNum} - ${keepfiles} ] -gt ${existsfilenum} ];then
			echo $j >> ${rmlog}
			#echo "rm -f ${j}" | bash
		fi
	done
done
	
}


help_fun(){
	echo "Discription:"
	echo "		This is a script to delete oracle goldengate trail files."
	echo "Parameters:"
	echo "		-p	specify a value for deleting action."
	echo "			avalable value: extract/replicat/all"
	echo "		-h	to get help."
}


##################################################################
#脚本的执行入口，获取参数
##################################################################
if [ $# -eq 0 ];then
	echo "You must specify a right parameter."
	echo "You can use -h or -H to get help."
	exit 99
fi
while (($#>=1))
do
	case `echo $1 | sed s/-//g | tr [a-z] [A-Z]` in
		H)
			help_fun          #执行帮助函数
			exit 0
		;;
		P)
			shift
			rmAction=$1       #获取-p参数的值
			shift
			continue
		;;
		*)
			echo "You must specify a right parameter."
			echo "You can use -h or -H to get help."
			exit 98
		;;
	esac
done

##################################################################
#记录日志
##################################################################
if [ ! -f ${rmlog} ];then
	touch ${rmlog}
fi
echo ""
echo "#################################`date +"%Y-%m-%d %H:%M:%S"`#################################" >> ${rmlog}

##################################################################
#判断-p参数的值，执行删除函数
##################################################################

case `echo ${rmAction} | tr [a-z] [A-Z]` in
	EXTRACT)
		deleteExtractfile          
		exit 0
	;;
	REPLICAT)
		deleteReplicatfile
		exit 0
	;;
	ALL)
		deleteExtractfile
		deleteReplicatfile
		exit 0
	;;
	*)
		echo "You must specify a valid value for -p."
		echo "You can use -h or -H to get help."
		exit 97
	;;
esac
	




