#!/bin/bash
############################################################
# comparison_tool.sh
# bcain@blackbirdit.com
############################################################

. ./.ct.cfg
CALLED_AS=`basename $0`
instance1=$1
port1=$PORT
instance2=$2
port2=$PORT
schema1=$3
schema2=$4

################################################################
# Parameter validation
################################################################
validate ()
{
    if [ -z "$instance1" ] || [ -z "$instance2" ] ; then
        echo "Usage: $CALLED_AS instance1[:port] instance2[:port] [schema1 [schema2]]"
        exit 1
    fi
    if [[ "$instance1" =~ ':' ]] ; then
        port1=`echo "$instance1" | cut -d ':' -f 2`
        instance1=`echo "$instance1" | cut -d ':' -f 1`
    fi
    if [[ "$instance2" =~ ':' ]] ; then
        port2=`echo "$instance2" | cut -d ':' -f 2`
        instance2=`echo "$instance2" | cut -d ':' -f 1`
    fi
}

################################################################
# Table comparisons
################################################################
table_comparison ()
{
    if [ ! -d "tables" ] ; then
        mkdir tables
    fi
    if [ -d "tables/instance1" ] ; then
        rm -f tables/instance1/*
    else
        mkdir tables/instance1
    fi
    if [ -d "tables/instance2" ] ; then
        rm -f tables/instance2/*
    else
        mkdir tables/instance2
    fi
    if [ -n "$schema1" ] ; then
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.tables where table_schema = '$schema1' and table_type = 'BASE TABLE' order by table_name" | while read tablename; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create table $schema1.$tablename" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> tables/instance1/$schema1
        done
        if [ -z "$schema2" ] ; then
            schema2=$schema1
        fi
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.tables where table_schema = '$schema2' and table_type = 'BASE TABLE' order by table_name" | while read tablename; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create table $schema2.$tablename" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> tables/instance2/$schema2
        done
    else
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.tables where table_schema = '$schemaname' and table_type = 'BASE TABLE' order by table_name" | while read tablename; do
                mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create table $schemaname.$tablename" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> tables/instance1/$schemaname
            done
        done
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.tables where table_schema = '$schemaname' and table_type = 'BASE TABLE' order by table_name" | while read tablename; do
                mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create table $schemaname.$tablename" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> tables/instance2/$schemaname
            done
        done
    fi
    table_on_1=0
    last_table=''
    last_show=''
    if [ -n "$schema1" ] ; then
        diffs=`diff tables/instance1/$schema1 tables/instance2/$schema2 | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
        if [ -n "$diffs" ] ; then
            summary="=============================================================\n"
            summary+="                      Tables Summary\n"
            summary+="-------------------------------------------------------------\n"
            while read instance_indicator table_name; do
                if [ "$instance_indicator" == "<" ] ; then
                    if [ $table_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_table"
                        echo -e "=============================================================\n\n"
                        summary+="$last_table - missing on $instance2:$port2:$schema2\n"
                    else
                        table_on_1=1
                    fi
                    echo "============================================================="
                    echo "$instance1:$port1:$schema1 "
                    last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create table $schema1.$table_name\G" | tail -n +3`
                    echo "$last_show"
                    echo "-------------------------------------------------------------"
                else
                    if [ "$last_table" != "$table_name" ] && [ $table_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_table"
                        echo -e "=============================================================\n\n"
                        table_on_1=0
                        summary+="$last_table - missing on $instance2:$port2:$schema2\n"
                    fi
                    if [ $table_on_1 -eq 0 ] ; then
                        echo "============================================================="
                        echo "$instance1:$port1:$schema1 is missing $table_name"
                        echo "-------------------------------------------------------------"
                        last_show=''
                        summary+="$table_name - missing on $instance1:$port1:$schema1\n"
                    else
                        table_on_1=0
                    fi
                    echo "$instance2:$port2:$schema2 "
                    this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create table $schema2.$table_name\G" | tail -n +3`
                    echo -e "$this_show"
                    if [ -n "$last_show" ] ; then
                        echo "-------------------------------------------------------------"
                        echo "Differences between $instance1:$port1:$schema1 (<) and $instance2:$port2:$schema2 (>)"
                        echo "-------------------------------------------------------------"
                        diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                        summary+="$table_name\n"
                    fi
                    echo -e "=============================================================\n\n"
                fi
                last_table="$table_name"
            done <<< "$diffs"
            if [ $table_on_1 -eq 1 ] ; then
                echo "$instance2:$port2:$schema2 is missing $last_table"
                echo -e "=============================================================\n\n"
                summary+="$last_table - missing on $instance2:$port2:$schema2\n"
            fi
            summary+="=============================================================\n"
            echo -e "$summary"
        else
            echo "No table differences found between $instance1:$port1:$schema1 and $instance2:$port2:$schema2"
        fi
    else
        summary=''
        schemas=`ls tables/instance1`
        while read schemafile; do
            if [ -z "$schemafile" ] ; then
                break
            fi
            if [ -e tables/instance2/$schemafile ] ; then
                diffs=`diff tables/instance1/$schemafile tables/instance2/$schemafile | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
                if [ -n "$diffs" ] ; then
                    summary+="-------------------------------------------------------------\n"
                    summary+="     $schemafile\n"
                    summary+="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n"
                    while read instance_indicator table_name; do
                        if [ "$instance_indicator" == "<" ] ; then
                            if [ $table_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_table"
                                echo -e "=============================================================\n\n"
                                summary+="$last_table - missing on $instance2:$port2:$schemafile\n"
                            else
                                table_on_1=1
                            fi
                            echo "============================================================="
                            echo "$instance1:$port1:$schemafile "
                            last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create table $schemafile.$table_name\G" | tail -n +3`
                            echo "$last_show"
                            echo "-------------------------------------------------------------"
                        else
                            if [ "$last_table" != "$table_name" ] && [ $table_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_table"
                                echo -e "=============================================================\n\n"
                                table_on_1=0
                                summary+="$last_table - missing on $instance2:$port2:$schemafile\n"
                            fi
                            if [ $table_on_1 -eq 0 ] ; then
                                echo "============================================================="
                                echo "$instance1:$port1:$schemafile is missing $table_name"
                                echo "-------------------------------------------------------------"
                                last_show=''
                                summary+="$table_name - missing on $instance1:$port1:$schemafile\n"
                            else
                                table_on_1=0
                            fi
                            echo "$instance2:$port2:$schemafile "
                            this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create table $schemafile.$table_name\G" | tail -n +3`
                            echo -e "$this_show"
                            if [ -n "$last_show" ] ; then
                                echo "-------------------------------------------------------------"
                                echo "Differences between $instance1:$port1:$schemafile (<) and $instance2:$port2:$schemafile (>)"
                                echo "-------------------------------------------------------------"
                                diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                                summary+="$table_name\n"
                            fi
                            echo -e "=============================================================\n\n"
                        fi
                        last_table="$table_name"
                    done <<< "$diffs"
                    if [ $table_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schemafile is missing $last_table"
                        echo -e "=============================================================\n\n"
                        summary+="$last_table - missing on $instance2:$port2:$schemafile\n"
                    fi
                    table_on_1=0
                    last_table=''
                    last_show=''
                else
                    echo "============================================================="
                    echo "No table differences found between $instance1:$port1:$schemafile and $instance2:$port2:$schemafile"
                    echo -e "=============================================================\n\n"
                fi
            else
                echo "============================================================="
                echo "No tables defined in schema $schemafile on $instance2:$port2"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all tables on $instance2:$port2 defined on $instance1:$port1\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"

        schemas=`ls tables/instance2`
        while read schemafile; do
            if [ -z $schemafile ] ; then
                break
            fi
            if [ ! -e tables/instance1/$schemafile ] ; then
                echo "============================================================="
                echo "No tables defined in schema $schemafile on $instance1:$port1"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all tables on $instance1:$port1 defined on $instance2:$port2\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"
        if [ -n "$summary" ] ; then
            echo -e "============================================================="
            echo -e "                      Tables Summary"
            echo -en "$summary"
            echo -e "=============================================================\n"
        fi
    fi
}


################################################################
# View comparisons
################################################################
view_comparison () {
    if [ ! -d "views" ] ; then
        mkdir views
    fi
    if [ -d "views/instance1" ] ; then
        rm -f views/instance1/*
    else
        mkdir views/instance1
    fi
    if [ -d "views/instance2" ] ; then
        rm -f views/instance2/*
    else
        mkdir views/instance2
    fi
    if [ -n "$schema1" ] ; then
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.views where table_schema = '$schema1' order by table_name" | while read viewname; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create view $schema1.$viewname" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> views/instance1/$schema1
        done
        if [ -z "$schema2" ] ; then
            schema2=$schema1
        fi
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.views where table_schema = '$schema2' order by table_name" | while read viewname; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create view $schema2.$viewname" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> views/instance2/$schema2
        done
    else
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.views where table_schema = '$schemaname' order by table_name" | while read viewname; do
                mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create view $schemaname.$viewname" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> views/instance1/$schemaname
            done
        done
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select table_name from information_schema.views where table_schema = '$schemaname' order by table_name" | while read viewname; do
                mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create view $schemaname.$viewname" | sed s/AUTO_INCREMENT=[0-9][0-9]*\ // >> views/instance2/$schemaname
            done
        done
    fi
    view_on_1=0
    last_view=''
    last_show=''
    if [ -n "$schema1" ] ; then
        diffs=`diff views/instance1/$schema1 views/instance2/$schema2 | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
        if [ -n "$diffs" ] ; then
            summary="=============================================================\n"
            summary+="                       Views Summary\n"
            summary+="-------------------------------------------------------------\n"
            while read instance_indicator view_name; do
                if [ "$instance_indicator" == "<" ] ; then
                    if [ $view_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_view"
                        echo -e "=============================================================\n\n"
                        summary+="$last_view - missing on $instance2:$port2:$schema2\n"
                    else
                        view_on_1=1
                    fi
                    echo "============================================================="
                    echo "$instance1:$port1:$schema1 "
                    last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -e "show create view $schema1.$view_name\G" | tail -n +2`
                    echo "$last_show"
                    echo "-------------------------------------------------------------"
                else
                    if [ "$last_view" != "$view_name" ] && [ $view_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_view"
                        echo -e "=============================================================\n\n"
                        view_on_1=0
                        summary+="$last_view - missing on $instance2:$port2:$schema2\n"
                    fi
                    if [ $view_on_1 -eq 0 ] ; then
                        echo "============================================================="
                        echo "$instance1:$port1:$schema1 is missing $view_name"
                        echo "-------------------------------------------------------------"
                        last_show=''
                        summary+="$view_name - missing on $instance1:$port1:$schema1\n"
                    else
                        view_on_1=0
                    fi
                    echo "$instance2:$port2:$schema2 "
                    this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -e "show create view $schema2.$view_name\G" | tail -n +2`
                    echo -e "$this_show"
                    if [ -n "$last_show" ] ; then
                        echo "-------------------------------------------------------------"
                        echo "Differences between $instance1:$port1:$schema1 (<) and $instance2:$port2:$schema2 (>)"
                        echo "-------------------------------------------------------------"
                        diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                        summary+="$view_name\n"
                    fi
                    echo -e "=============================================================\n\n"
                fi
                last_view="$view_name"
            done <<< "$diffs"
            if [ $view_on_1 -eq 1 ] ; then
                echo "$instance2:$port2:$schema2 is missing $last_view"
                echo -e "=============================================================\n\n"
                summary+="$last_view - missing on $instance2:$port2:$schema2\n"
            fi
            summary+="=============================================================\n"
            echo -e "$summary"
        else
            echo "No view differences found between $instance1:$port1:$schema1 and $instance2:$port2:$schema2"
        fi
    else
        summary=''
        schemas=`ls views/instance1`
        while read schemafile; do
            if [ -z "$schemafile" ] ; then
                break
            fi
            if [ -e views/instance2/$schemafile ] ; then
                diffs=`diff views/instance1/$schemafile views/instance2/$schemafile | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
                if [ -n "$diffs" ] ; then
                    summary+="-------------------------------------------------------------\n"
                    summary+="     $schemafile\n"
                    summary+="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n"
                    while read instance_indicator view_name; do
                        if [ "$instance_indicator" == "<" ] ; then
                            if [ $view_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_view"
                                echo -e "=============================================================\n\n"
                                summary+="$last_view - missing on $instance2:$port2:$schemafile\n"
                            else
                                view_on_1=1
                            fi
                            echo "============================================================="
                            echo "$instance1:$port1:$schemafile "
                            last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -e "show create view $schemafile.$view_name\G" | tail -n +2`
                            echo "$last_show"
                            echo "-------------------------------------------------------------"
                        else
                            if [ "$last_view" != "$view_name" ] && [ $view_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_view"
                                echo -e "=============================================================\n\n"
                                view_on_1=0
                                summary+="$last_view - missing on $instance2:$port2:$schemafile\n"
                            fi
                            if [ $view_on_1 -eq 0 ] ; then
                                echo "============================================================="
                                echo "$instance1:$port1:$schemafile is missing $view_name"
                                echo "-------------------------------------------------------------"
                                last_show=''
                                summary+="$view_name - missing on $instance1:$port1:$schemafile\n"
                            else
                                view_on_1=0
                            fi
                            echo "$instance2:$port2:$schemafile "
                            this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -e "show create view $schemafile.$view_name\G" | tail -n +2`
                            echo -e "$this_show"
                            if [ -n "$last_show" ] ; then
                                echo "-------------------------------------------------------------"
                                echo "Differences between $instance1:$port1:$schemafile (<) and $instance2:$port2:$schemafile (>)"
                                echo "-------------------------------------------------------------"
                                diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                                summary+="$view_name\n"
                            fi
                            echo -e "=============================================================\n\n"
                        fi
                        last_view="$view_name"
                    done <<< "$diffs"
                    if [ $view_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schemafile is missing $last_view"
                        echo -e "=============================================================\n\n"
                        summary+="$last_view - missing on $instance2:$port2:$schemafile\n"
                    fi
                    view_on_1=0
                    last_view=''
                    last_show=''
                else
                    echo "============================================================="
                    echo "No view differences found between $instance1:$port1:$schemafile and $instance2:$port2:$schemafile"
                    echo -e "=============================================================\n\n"
                fi
            else
                echo "============================================================="
                echo "No views defined in schema $schemafile on $instance2:$port2"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all views on $instance2:$port2 defined on $instance1:$port1\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"

        schemas=`ls views/instance2`
        while read schemafile; do
            if [ -z $schemafile ] ; then
                break
            fi
            if [ ! -e views/instance1/$schemafile ] ; then
                echo "============================================================="
                echo "No views defined in schema $schemafile on $instance1:$port1"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all views on $instance1:$port1 defined on $instance2:$port2\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"
        if [ -n "$summary" ] ; then
            echo -e "============================================================="
            echo -e "                       Views Summary"
            echo -en "$summary"
            echo -e "=============================================================\n"
        fi
    fi
}

################################################################
# Trigger comparisons
################################################################
trigger_comparison () {
    if [ ! -d "triggers" ] ; then
        mkdir triggers
    fi
    if [ -d "triggers/instance1" ] ; then
        rm -f triggers/instance1/*
    else
        mkdir triggers/instance1
    fi
    if [ -d "triggers/instance2" ] ; then
        rm -f triggers/instance2/*
    else
        mkdir triggers/instance2
    fi
    if [ -n "$schema1" ] ; then
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select trigger_name from information_schema.triggers where trigger_schema = '$schema1' order by trigger_name" | while read triggername; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create trigger $schema1.$triggername" >> triggers/instance1/$schema1
        done
        if [ -z "$schema2" ] ; then
            schema2=$schema1
        fi
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select trigger_name from information_schema.triggers where trigger_schema = '$schema2' order by trigger_name" | while read triggername; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create trigger $schema2.$triggername" >> triggers/instance2/$schema2
        done
    else
        mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "select trigger_name from information_schema.triggers where trigger_schema = '$schemaname' order by trigger_name" | while read triggername; do
                mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -N -e "show create trigger $schemaname.$triggername" >> triggers/instance1/$schemaname
            done
        done
        mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select schema_name from information_schema.schemata where schema_name not in ('information_schema','mysql','performance_schema')" | while read schemaname; do
            mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "select trigger_name from information_schema.triggers where trigger_schema = '$schemaname' order by trigger_name" | while read triggername; do
                mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -N -e "show create trigger $schemaname.$triggername" >> triggers/instance2/$schemaname
            done
        done
    fi
    trigger_on_1=0
    last_trigger=''
    last_show=''
    if [ -n "$schema1" ] ; then
        diffs=`diff triggers/instance1/$schema1 triggers/instance2/$schema2 | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
        if [ -n "$diffs" ] ; then
            summary="=============================================================\n"
            summary+="                     Triggers Summary\n"
            summary+="-------------------------------------------------------------\n"
            while read instance_indicator trigger_name; do
                if [ "$instance_indicator" == "<" ] ; then
                    if [ $trigger_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_trigger"
                        echo -e "=============================================================\n\n"
                        summary+="$last_trigger - missing on $instance2:$port2:$schema2\n"
                    else
                        trigger_on_1=1
                    fi
                    echo "============================================================="
                    echo "$instance1:$port1:$schema1 "
                    last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -e "show create trigger $schema1.$trigger_name\G" | tail -n +2`
                    echo "$last_show"
                    echo "-------------------------------------------------------------"
                else
                    if [ "$last_trigger" != "$trigger_name" ] && [ $trigger_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schema2 is missing $last_trigger"
                        echo -e "=============================================================\n\n"
                        trigger_on_1=0
                        summary+="$last_trigger - missing on $instance2:$port2:$schema2\n"
                    fi
                    if [ $trigger_on_1 -eq 0 ] ; then
                        echo "============================================================="
                        echo "$instance1:$port1:$schema1 is missing $trigger_name"
                        echo "-------------------------------------------------------------"
                        last_show=''
                        summary+="$trigger_name - missing on $instance1:$port1:$schema1\n"
                    else
                        trigger_on_1=0
                    fi
                    echo "$instance2:$port2:$schema2 "
                    this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -e "show create trigger $schema2.$trigger_name\G" | tail -n +2`
                    echo -e "$this_show"
                    if [ -n "$last_show" ] ; then
                        echo "-------------------------------------------------------------"
                        echo "Differences between $instance1:$port1:$schema1 (<) and $instance2:$port2:$schema2 (>)"
                        echo "-------------------------------------------------------------"
                        diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                        summary+="$trigger_name\n"
                    fi
                    echo -e "=============================================================\n\n"
                fi
                last_trigger="$trigger_name"
            done <<< "$diffs"
            if [ $trigger_on_1 -eq 1 ] ; then
                echo "$instance2:$port2:$schema2 is missing $last_trigger"
                echo -e "=============================================================\n\n"
                summary+="$last_trigger - missing on $instance2:$port2:$schema2\n"
            fi
            summary+="=============================================================\n"
            echo -e "$summary"
        else
            echo "No trigger differences found between $instance1:$port1:$schema1 and $instance2:$port2:$schema2"
        fi
    else
        summary=''
        schemas=`ls triggers/instance1`
        while read schemafile; do
            if [ -z "$schemafile" ] ; then
                break
            fi
            if [ -e triggers/instance2/$schemafile ] ; then
                diffs=`diff triggers/instance1/$schemafile triggers/instance2/$schemafile | egrep '<'\|'>' | sed 's/\([\<\>] [a-zA-Z_0-9$][a-zA-Z_0-9$]*\).*/\1/' | sort`
                if [ -n "$diffs" ] ; then
                    summary+="-------------------------------------------------------------\n"
                    summary+="     $schemafile\n"
                    summary+="- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n"
                    while read instance_indicator trigger_name; do
                        if [ "$instance_indicator" == "<" ] ; then
                            if [ $trigger_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_trigger"
                                echo -e "=============================================================\n\n"
                                summary+="$last_trigger - missing on $instance2:$port2:$schemafile\n"
                            else
                                trigger_on_1=1
                            fi
                            echo "============================================================="
                            echo "$instance1:$port1:$schemafile "
                            last_show=`mysql -h $instance1 -P $port1 -u $USER -p"$PASSWORD" -e "show create trigger $schemafile.$trigger_name\G" | tail -n +3`
                            echo "$last_show"
                            echo "-------------------------------------------------------------"
                        else
                            if [ "$last_trigger" != "$trigger_name" ] && [ $trigger_on_1 -eq 1 ] ; then
                                echo "$instance2:$port2:$schemafile is missing $last_trigger"
                                echo -e "=============================================================\n\n"
                                trigger_on_1=0
                                summary+="$last_trigger - missing on $instance2:$port2:$schemafile\n"
                            fi
                            if [ $trigger_on_1 -eq 0 ] ; then
                                echo "============================================================="
                                echo "$instance1:$port1:$schemafile is missing $trigger_name"
                                echo "-------------------------------------------------------------"
                                last_show=''
                                summary+="$trigger_name - missing on $instance1:$port1:$schemafile\n"
                            else
                                trigger_on_1=0
                            fi
                            echo "$instance2:$port2:$schemafile "
                            this_show=`mysql -h $instance2 -P $port2 -u $USER -p"$PASSWORD" -e "show create trigger $schemafile.$trigger_name\G" | tail -n +3`
                            echo -e "$this_show"
                            if [ -n "$last_show" ] ; then
                                echo "-------------------------------------------------------------"
                                echo "Differences between $instance1:$port1:$schemafile (<) and $instance2:$port2:$schemafile (>)"
                                echo "-------------------------------------------------------------"
                                diff <(echo "$last_show") <(echo "$this_show") | egrep '<'\|'>'
                                summary+="$trigger_name\n"
                            fi
                            echo -e "=============================================================\n\n"
                        fi
                        last_trigger="$trigger_name"
                    done <<< "$diffs"
                    if [ $trigger_on_1 -eq 1 ] ; then
                        echo "$instance2:$port2:$schemafile is missing $last_trigger"
                        echo -e "=============================================================\n\n"
                        summary+="$last_trigger - missing on $instance2:$port2:$schemafile\n"
                    fi
                    trigger_on_1=0
                    last_trigger=''
                    last_show=''
                else
                    echo "============================================================="
                    echo "No trigger differences found between $instance1:$port1:$schemafile and $instance2:$port2:$schemafile"
                    echo -e "=============================================================\n\n"
                fi
            else
                echo "============================================================="
                echo "No triggers defined in schema $schemafile on $instance2:$port2"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all triggers on $instance2:$port2 defined on $instance1:$port1\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"

        schemas=`ls triggers/instance2`
        while read schemafile; do
            if [ -z $schemafile ] ; then
                break
            fi
            if [ ! -e triggers/instance1/$schemafile ] ; then
                echo "============================================================="
                echo "No triggers defined in schema $schemafile on $instance1:$port1"
                echo -e "=============================================================\n\n"
                summary+="-------------------------------------------------------------\n"
                summary+="$schemafile is missing all triggers on $instance1:$port1 defined on $instance2:$port2\n"
                summary+="-------------------------------------------------------------\n"
            fi
        done <<< "$schemas"
        if [ -n "$summary" ] ; then
            echo -e "============================================================="
            echo -e "                     Triggers Summary"
            echo -en "$summary"
            echo -e "=============================================================\n"
        fi
    fi
}

case $CALLED_AS in
    "table_comparison"   )
        validate
        table_comparison
        ;;
    "view_comparison"    )
        validate
        view_comparison
        ;;
    "trigger_comparison" )
        validate
        trigger_comparison
        ;;

    *                    )
        echo "Usage: Use one of the alias names for comparison_tool instead"
        exit 1
        ;;
esac
