function data = ubinary(filename)
    % The general scheme that Labview uses when writing data to a binary
    % file is to just write one piece of data after another. It is
    % impossible to parse unless you know what data is written and in what
    % order. The uBinary VI creates a header that contains the variable
    % names and types of the data, which can then be written at the
    % beginning of the file. This code assumes that the binary file
    % contains such a header. Otherwise I expect it will fail dramatically.
    % (Compared to when it has a header and only fails embarassingly.)
    
    % For most typical data it is written straight to the binary file -
    % This is stuff like integers, floats, any sort of 0-dimensional or
    % scalar data. For data in larger dimensions, 1d arrays, n-dimensional
    % arrays, strings (which are 1d character arrays), clusters, and the
    % like it gets more complicated. Strings have a length byte preceeding
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


    % open the binary file that is written with Little Endian byte
    % order. This is NOT the default labview byte order - plan accordingly!
    f = fopen(filename,'r');

    %% Read in Header from ubinary.vi
    % first read in a 1d array of strings containing the variable names
    names = read_array(f,[1 48],{});
    % now read in a 1d array of integers that contain type data
    type_array = read_array(f,[1 5],{});
    
    %% Read in actual data
    [data,~,~] = read_cluster(f,type_array,names,inf);
    
    fclose(f);
end

function data = read_data(f,current_type,n)
    if nargin<3
        n=1;
    end
    types{1}  = 'int8';
    types{2}  = 'int16';
    types{3}  = 'int32';
    types{4}  = 'int64';
    types{5}  = 'uint8';
    types{6}  = 'uint16';
    types{7}  = 'uint32';
    types{8}  = 'uint64';    
    types{9}  = 'single';
    types{10} = 'double';
    types{33} = 'bool';
    
    if  (current_type == 48) || ... % string
        (current_type == 51) || ... % Picture
        (current_type == 55) || ... % DAC resource name
        (current_type == 112)       % VISA resource name
        data = read_string(f);
    elseif current_type == 84
        data = read_waveform(f);
    else
        data = fread(f,n,[types{current_type} '=>' types{current_type}]);
    end
end

function data = read_string(f)
    byte = 2.^[0 8 16 32]'; % little endian
    x = fread(f,4);
    dim = sum(x.*byte);
    data = transpose(fread(f,dim,'char=>char'));
end

function data = read_waveform(f)
    data.timestamp1 = fread(f,1,'uint64=>uint64');
    data.timestamp2 = int64(uint32(fread(f,1,'int64=>int64'))-2082844800);
    data.dt = fread(f,1,'double=>double');
    data.Y = read_array(f,[1 10],{});
    data.attributes = fread(f,29);
end

function [data,type_array,names] = read_array(f,type_array,names)
    byte = 2.^[0 8 16 32]'; % little endian

    % N is the dimension of the array. Pop this off of the type array
    N = type_array(1);
    type_array = type_array(2:end);
    dim = zeros(1,N);
    % Now read in the size of each dimension of the array.
    for i=1:N
        x = fread(f,4);
        dim(i) = sum(x.*byte);
    end
    
    % Pop the type of the array and the variable name off of the queue.
    current_type = type_array(1);
    type_array = type_array(2:end);
    names = names(2:end);
    
    if length(dim)==1
        dim = [dim 1];
    end
    data = transpose(cell(dim));
    
    if current_type==80
        n = type_array(1);
        type_array = type_array(2:end);
        if prod(dim)>1
            for i=1:(prod(dim)-1)
                [data{i},~,~] = read_cluster(f,type_array,names,n);
            end
            [data{i+1},type_array,names] = read_cluster(f,type_array,names,n);
        else
            [data{1},type_array,names] = read_cluster(f,type_array,names,n);
        end
    elseif and(current_type>0,current_type<=33)
            data = read_data(f,current_type,prod(dim));
    else
        for i=1:prod(dim)
            data{i} = read_data(f,current_type);
        end
    end
    
    if length(dim(dim>1))==2
        data = reshape(data,dim(2),dim(1));
    end
    
    data = transpose(data);
end

function [data,type_array,names] = read_cluster(f,type_array,names,n)
    data = [];
    % no_name_index counts how many variables have no given name. We name
    % these unnamedX, where X is a unique index.
    no_name_index = 1;
    
    %% Loop through data in this cluster and read it in
    while ~isempty(type_array) && n>0
        % pop off the current data type off the queue
        current_type = type_array(1);
        type_array = type_array(2:end);
        
        % pop off the current variable name
        current_name = names(1);
        names = names(2:end);
        
        if strcmp(current_name,'')
            current_name = {strcat('unnamed',num2str(no_name_index))};
            no_name_index=no_name_index+1;
        end
        
        if current_type == 64
            [x,type_array,names] = read_array(f,type_array,names);
        elseif current_type == 80
            m = type_array(1);
            type_array = type_array(2:end);
            [x,type_array,names] = read_cluster(f,type_array,names,m);
        else
            x = read_data(f,current_type);
        end
        [~] = x;
        command = strcat('data.',genvarname(current_name),' = x;');
%         fprintf([command{1} '\n']);
        eval(command{1})

        n = n-1;
    end
end