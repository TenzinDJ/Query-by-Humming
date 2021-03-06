#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <iostream>

#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>

#include "util.h"
#include "datalist.h"
#include "asm.h"

float* get_sequence(char *name,int *l)
{
    FILE *fp;
    int line;
    float *sequence;
    if((fp=fopen(name,"r"))==NULL)
    {
        fprintf(stderr,"Open file failed!\n");
        return NULL;
    }
    fscanf(fp,"%d",&line);
    sequence=(float *)malloc(sizeof(float)*line);
    for(int i=0;i<line;i++)
    {
        if(fscanf(fp,"%f",&sequence[i])==EOF)
        {
            *l=i;
            fclose(fp);
            return sequence;
        }
    }
    fclose(fp);

    *l=line;
    return sequence;
}

void print_sequence(float *seq,int line)
{
    printf("line is %d,seq is:\n");
    for(int i=0;i<line;i++)
    {
        printf("%lf\n",seq[i]);
    }
}

int isreg(char *filename)
{
    char *temp;

    temp=strrchr(filename,(int)'.');
    if(temp!=NULL) return 1;
    else return 0;
}

int istxt(char *filename)
{
    char *temp,*temp2;

    temp=strstr(filename,".txt");
    temp2=strstr(filename,".txt~");//drop the backup file
    if(temp!=NULL&&temp2==NULL) return 1;
    else return 0;
}

int main(int argc, char **argv)
{
    float *query,*sequence;
    int qline,sline;
    float t1,t2;
    float r;
    int scaned_file=0;
    int *accum_length;
    int *seq_length;
    float *all_seq;
    float *small;
    distance dist[400];

    if(argc!=4) error(2);
    r=atof(argv[3]);

    //initialize cuda device
    cudaSetDevice( 1 );    
    cudaThreadSynchronize();

    //first get the query sequence
    query=get_sequence(argv[1],&qline);
    if(query==NULL)
    {
        perror("get query error!\n");
        return -1;
    }

    if(isreg(argv[2])&&istxt(argv[2]))
    {
        fprintf(stderr,"file will compare with a library! So the third parameter should be a directory\n");
        return -1;
    }
    else
    {
        DIR *dp;
        struct dirent *entry;
        struct stat statbuf;

        if((dp=opendir(argv[2]))==NULL)
        {
            fprintf(stderr,"cannot open directory: %s\n",argv[2]);
            return -1;
        }

        chdir(argv[2]);//from current directory to the specified directory

        t1=clock();
        while((entry=readdir(dp))!=NULL)
        {
            lstat(entry->d_name,&statbuf);
            //get all the sequences in a directory
            if(S_ISREG(statbuf.st_mode)&&istxt(entry->d_name))
            {
                sequence=get_sequence(entry->d_name,&sline);
                if(sequence==NULL)
                {
                    perror("get query error!\n");
                    return -1;
                }

                //save the sequence in a linkedlist
                seq *s=(seq *)malloc(sizeof(seq));
                s->length=sline;
                strcpy(s->name,entry->d_name);
                s->data=sequence;

                append(s);
                scaned_file++;

                //printf("file %d:%s,length is %d\n",scaned_file,entry->d_name,sline);
            }
        }
        t2=clock();
        //printf("time of get all the sequence is %lf\n",(t2-t1)/CLOCKS_PER_SEC);
    }

    //traverse();

    //cal the accumulated length used for index
    t1=clock();
    accum_length=(int *)malloc(sizeof(int)*scaned_file);
    seq_length=(int *)malloc(sizeof(int)*scaned_file);
    const seq *temp=iterator();
    int sum=0;
    for(int i=0;i<scaned_file;i++)
    {
        accum_length[i]=sum;
        seq_length[i]=temp->length;
        sum+=temp->length;
        temp=temp->next;
    }


    //copy all the sequences to a whole array
    all_seq=(float *)malloc(sizeof(float)*sum);
    temp=iterator();
    int i=0;
    while(temp!=NULL)
    {
        for(int j=0;j<temp->length;j++)
        {
            all_seq[i++]=temp->data[j];
        }
        temp=temp->next;
    }
    t2=clock();
    //printf("time of arrangement is %lf\n",(t2-t1)/CLOCKS_PER_SEC);


    t1=clock();
    small=Asm(query,qline,scaned_file,all_seq,sum,seq_length,accum_length,r);
    t2=clock();
    //printf("time of all asm is %lf\n",(t2-t1)/CLOCKS_PER_SEC);
    temp=iterator();
    for(int i=0;i<scaned_file;i++)
    {
                dist[i].dis=small[i];
                strcpy(dist[i].name,temp->name);
                temp=temp->next;
    }

    
    t1=clock();
    qsort(dist,scaned_file,sizeof(distance),com);

    int rank;
    char * query_name=strrchr(argv[1],'/');
    query_name++;
    for(int i=0;i<scaned_file;i++)
    {
        //printf("(%d) file %s: %lf\n",i+1,dist[i].name,dist[i].dis);
        if(strcmp(query_name,dist[i].name)==0)
        {
            rank=i+1;
        }
    }

    printf("search file: %s, rank is %d\n\n",query_name,rank);
    t2=clock();
    //printf("time of sort is %lf\n\n",(t2-t1)/CLOCKS_PER_SEC);

    free(query);

    return 0;
}
