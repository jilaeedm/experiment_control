function output = parse_binary(str,ptr)
    % PARSE_BINARY(file,offset)     
    %   Opens a Labview binary file (with Grau approved
    %   header). Stores the binary data in a self describing struct.
    %
    % The general scheme that Labview uses when writing data to a binary
    % file is to just write one piece of data after another. It is
    % impossible to parse unless you know what data is written and in what
    % order. The uBinary VI creates a header that contains the variable
    % names and types of the data, which can then be written at the
    % beginning of the file. This code assumes that the binary file
    % contains such a header. Otherwise I expect it will fail dramatically.
    % (Compared to when it has a header and only fails embarassingly.)
    %
    % For most typical data it is written straight to the binary file -
    % This is stuff like integers, floats, any sort of 0-dimensional or
    % scalar data. For data in larger dimensions, 1d arrays, n-dimensional
    % arrays, strings (which are 1d character arrays), clusters, and the
    % like it gets more complic. Strings have a length byte preceeding
    % them, and then character bytes of the string are written. Arrays have
    % a length byte as well, and then each element is written, taking up as
    % many bytes as its data type dictates. Clusters write each of their
    % elements sequentially, with no indication as to how many elements are
    % in the cluster. Most things in Labview can be broken down into some
    % sort of nested conflation of strings, arrays, and clusters. There are
    % however some data types I don't understand even yet, such as the
    % Picture data type.
    % the dimensions of arrays are written prior. Each dimension
    % has 4 bytes.
    %
    %
    % open the binary file that is written with Little Endian byte
    % order. This is NOT the default labview byte order - plan accordingly!

    %% Read in Header from ubinary.vi
    % first read in a 1d array of strings containing the variable names
    [ptr,names] = read_array(str,ptr,[1 48],{});

    % now read in a 1d array of integers that contain type data
    [ptr,type_array] = read_array(str,ptr,[1 5],{});

    %% Read in actual data
    [~,output,~,~] = read_cluster(str,ptr,type_array,names,inf);
end

function type_string=convert_type(type_enum)
    switch type_enum
        case 1
            type_string = 'int8';
        case 2
            type_string = 'int16';
        case 3
            type_string = 'int32';
        case 4
            type_string = 'int64';
        case 5
            type_string = 'uint8';
        case 6
            type_string = 'uint16';
        case 7
            type_string = 'uint32';
        case 8
            type_string = 'uint64';
        case 9
            type_string = 'single';
        case 10
            type_string = 'double';
        case 22
            type_string = 'uint16'; % enum
        case 23
            type_string = 'uint32'; % tabs
        case 33
            type_string = 'bool';
        otherwise
            type_string = 'uint32';
    end
end

function n=type_size(type_enum)
    switch type_enum
        case {2,6,22}
            n=2;
        case {3,7,9,23}
            n=4;
        case {4,8,10}
            n=8;
        otherwise
            n=1;            
    end
end

function [ptr,data] = read_data(str,ptr,current_type,n)
    switch current_type
        case {48, 51, 55, 112} % string, Picture, DAC resource, VISA resource
            [ptr,data] = read_string(str,ptr);
        case 84
            [ptr,data] = read_waveform(str,ptr);
        case 33
            data = logical(str(ptr:ptr+n-1));
            ptr = ptr+n;
        otherwise
            data = typecast(str(ptr:ptr+n*type_size(current_type)-1),convert_type(current_type));
            ptr = ptr+n*type_size(current_type);
    end
end

function [ptr,data] = read_string(str,ptr)
    dim = typecast(str(ptr:ptr+4-1),'uint32');
    ptr = ptr + 4;
    data = char(str(ptr:ptr+dim-1));
    ptr = ptr + dim;
end

function [ptr,data] = read_waveform(str,ptr)
    data.timestamp1 = typecast(str(ptr:ptr+8-1),'uint64');
    ptr = ptr + 8;
    data.timestamp2 = int64(uint32(typecast(str(ptr:ptr+8-1),'uint64'))-2082844800);
    ptr = ptr + 8;
    data.dt = typecast(str(ptr:ptr+8-1),'double');
    ptr = ptr + 8;
    [ptr,data.Y] = read_array(str,ptr,[1 10],{});
    data.attributes = str(ptr:ptr+29-1);
    ptr = ptr + 29;
end

function [ptr,data,type_array,names] = read_array(str,ptr,type_array,names)
    % N is the dimension of the array. Pop this off of the type array
    N = double(type_array(1));
    type_array = type_array(2:end);
    % Now read in the size of each dimension of the array.
    dim = double(typecast(str(ptr:ptr+4*N-1),'uint32'));
    ptr = ptr + 4*N;

    % Pop the type of the array and the variable name off of the queue.
    current_type = type_array(1);
    type_array = type_array(2:end);
    names = names(2:end);
    
    if length(dim)==1
        dim = [dim 1];
    end
    
    
    if current_type==80
        n = type_array(1);
        type_array = type_array(2:end);
        if prod(dim)>1
            [ptr,data(1:prod(dim)),~,~] = read_cluster(str,ptr,type_array,names,n);
            if prod(dim)>2
                for i=2:(prod(dim)-1)
                    [ptr,data(i),~,~] = read_cluster(str,ptr,type_array,names,n);
                end
            end
            [ptr,data(prod(dim)),type_array,names] = read_cluster(str,ptr,type_array,names,n);
        else
            [ptr,data,type_array,names] = read_cluster(str,ptr,type_array,names,n);
        end
    elseif and(current_type>0,current_type<=33)
            [ptr,data] = read_data(str,ptr,current_type,prod(dim));
    else
        data = transpose(cell(double(dim)));
        for i=1:prod(dim)
            [ptr,data{i}] = read_data(str,ptr,current_type,1);
        end
    end
    
    data = transpose(data);
end

function [ptr,data,type_array,names] = read_cluster(str,ptr,type_array,names,n)
    data = struct;
    % no_name_index counts how many variables have no given name. We name
    % these unnamedX, where X is a unique index.
    no_name_index = 1;
    
    %% Loop through data in this cluster and read it in
    while ~isempty(type_array) && n>0
        % pop off the current data type off the queue
        current_type = type_array(1);
        type_array = type_array(2:end);
        
        % pop off the current variable name
        current_name = names{1};
        names = names(2:end);
        
        if strcmp(current_name,'')
            current_name = strcat('unnamed',num2str(no_name_index));
            no_name_index=no_name_index+1;
        end
        
        switch current_type
            case 64
                [ptr,x,type_array,names] = read_array(str,ptr,type_array,names);
            case 80
                m = type_array(1);
                type_array = type_array(2:end);
                [ptr,x,type_array,names] = read_cluster(str,ptr,type_array,names,m);
            otherwise
                [ptr,x] = read_data(str,ptr,current_type,1);
        end

        data.(genvar(current_name)) = x;

        n = n-1;
    end
end

function varname = genvar(candidate)
varname = candidate;
if ~isvarname(varname) % Short-circuit if varname already legal
    % Insert x if the first column is non-letter.
    varname = regexprep(varname,'^\s*+([^A-Za-z])','x$1', 'once');

    % Replace whitespace with camel case
    [~, afterSpace] = regexp(varname,'\S\s+\S');
    for j=afterSpace
        varname(j) = upper(varname(j));
    end
    varname = regexprep(varname,'\s+','');
    if (isempty(varname))
        varname = 'x';
    end
    % Remove non-word character
    varname = regexprep(varname,'[^A-Za-z_0-9]','');

    % Prepend keyword with 'x' and camel case.
    if iskeyword(varname)
        varname = ['x' upper(varname(1)) varname(2:end)];
    end

    % Truncate varname to NAMLENGTHMAX
    varname = varname(1:min(length(varname),namelengthmax));
end
end
