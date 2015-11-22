clear
addpath(genpath('code'));
warning('off','all');    

annotations.cellLines = readtable('input/Dream/molecular/cell_info.csv', 'Delimiter', ',');
annotations.drugs = readtable('input/Dream/synergy/Drugs_mapped.txt', 'Delimiter', '\t');
annotations.drugs.Target = cellfun(@(targets) strsplit(targets, ';'), annotations.drugs.Target, 'UniformOutput', false);

[~, CL_perm] = sort(annotations.cellLines.Tissue__General_);
annotations.cellLines = annotations.cellLines(CL_perm, :);

experiment_type = 'leaderBoard';

%% Load signaling interactome from ACSN together with 55 functional classes relevant to cancer
[ ACSN ] = import_ACSN();


%% Read Monotherapy data and impute missing values based on Dual Layer method
% [ Mono ] = read_MonoTherapy(annotations, 'input/Dream/synergy/ch2_leaderBoard_monoTherapy.csv' );
[ Mono ] = read_MonoTherapy(annotations, 'input/Dream/synergy/ch1_train_combination_and_monoTherapy.csv' );

% X = Mono.Drug_sensitivity; X(isnan(X)) = 0;
% Y = double(logical(X));
% XX = X'*X ./ (Y'*Y);
% XX(isnan(XX)) = 0;
% XX(XX > 0) = (nonzeros(XX) - min(nonzeros(XX))) / (max(nonzeros(XX)) - min(nonzeros(XX)));
% SenSim = XX;
% SenSim = SenSim - diag(diag(SenSim));
% SenSim(SenSim < 0.9) = 0;
% clustergram(SenSim, 'RowLabels', annotations.drugs.ChallengeName, 'ColumnLabels', annotations.drugs.ChallengeName, 'Linkage', 'average', 'ColorMap', colormap(flipud(redgreencmap())), 'OPTIMALLEAFORDER', true)


%% Cellline-Celline Similarity Network
C2C = Construct_C2C(annotations, 'expression_only', true);


%% Drug-Drug Similarity Network
D2D = Construct_D2D(ACSN, annotations);


%% Read Leadership board
    Leadership = readtable('input/Dream/submission/leadership/synergy_matrix.csv', 'ReadRowNames', true);
    pair_names = cellfun(@(x) strsplit(x, '.'), Leadership.Properties.RowNames, 'UniformOutput', false);
    pair_idx = cell(numel(pair_names), 1);
    for i = 1:numel(pair_names)
        pair_idx{i}{1} = find(strcmp(pair_names{i}{1}, annotations.drugs.ChallengeName));
        pair_idx{i}{2} = find(strcmp(pair_names{i}{2}, annotations.drugs.ChallengeName));        
    end
    sorted_CL = Leadership.Properties.VariableNames;

%% Read LINCS dataset
    LINCS_ds = parse_gct('input/LINCS/final/LINCS_subset.gct');

%     % If we need to fgind replicates
%     [x, y, z] = unique(strcat(LINCS_ds.cdesc(:, 1), LINCS_ds.cdesc(:,7))); 
    
    LINCS_celllines = LINCS_ds.cdesc(:, 1);
    LINCS_celllines(strcmp(LINCS_celllines, 'BT20')) = {'BT-20'};
    LINCS_celllines(strcmp(LINCS_celllines, 'HT29')) = {'HT-29'};    
    LINCS_celllines(strcmp(LINCS_celllines, 'MDAMB231')) = {'MDA-MB-231'};    
    
    LINCS_drugs = LINCS_ds.cdesc(:, 7);
    LINCS_expression_matrix = LINCS_ds.mat; % TODO: Should we column normalize to ensure constant transcriptional activity for each drug?
    LINCS_expression_within_groups = zeros(numel(ACSN.class_names), size(LINCS_expression_matrix, 2));
    
    
    for g = 1:numel(ACSN.class_genes)
        [~, rows] = ismember(ACSN.class_genes{g}, LINCS_ds.rdesc(:, 7));
        rows(rows == 0) = [];
        LINCS_expression_within_groups(g, :) = arrayfun(@(col) mean(LINCS_expression_matrix(rows, col)), 1:size(LINCS_expression_matrix, 2));        
    end
    
    
    [~, cl_idx] = ismember(LINCS_celllines, annotations.cellLines.Sanger_Name);
    Dream2LINCS= readtable('/home/shahin/Dropbox/Dream/experiment/input/LINCS/final/preliminary_mapping.csv');
    
    Expr_DS = cell(size(annotations.drugs, 1), size(annotations.cellLines, 1));
    for i = 1:size(LINCS_expression_matrix, 2)        
        rows = find(ismember(Dream2LINCS.ID, LINCS_drugs{i}));        
        % TODO: Should we use aggregated scores in groups (probably), or all
        % genes without grouping (unlikely)?
%         Expr_DS(rows, cl_idx(i)) = {LINCS_expression_matrix(:, i)};
        % *** OR ***
        Expr_DS(rows, cl_idx(i)) = {LINCS_expression_within_groups(:, i)};
    end
    

    % TODO: Use 2 Layer method to impute missing values
    
    
%% Compute Synergy scores
    Synergy_score = 2;    
    Confidence_mat = nan(size(Leadership));
    for pIdx = 1:numel(pair_idx)
        d1 = pair_idx{pIdx}{1};
        d2 = pair_idx{pIdx}{2};
        for cIdx = 1:size(annotations.cellLines, 1)
            Confidence_mat(pIdx, cIdx) = Synergy_score * rand(1);
        end
    end
    

%% Export
    synergy_threshold = 1; % TODO: What is the optimal threshold??
    
    fd_syn = fopen(fullfile('output', 'predictions', experiment_type, 'synergy_matrix.csv'), 'w');
    fd_conf = fopen(fullfile('output', 'predictions', experiment_type, 'confidence_matrix.csv'), 'w');
    for cIdx = 1:size(annotations.cellLines, 1)
        fprintf(fd_syn, ',%s', sorted_CL{cIdx});
        fprintf(fd_conf, ',%s', sorted_CL{cIdx});
    end
    fprintf(fd_syn, '\n');
    fprintf(fd_conf, '\n');    
    
    for pIdx = 1:numel(pair_idx)
        fprintf(fd_syn, '%s.%s', pair_names{pIdx}{1}, pair_names{pIdx}{2});
        fprintf(fd_conf, '%s.%s', pair_names{pIdx}{1}, pair_names{pIdx}{2});
        for cIdx = 1:size(annotations.cellLines, 1)
            fprintf(fd_syn, ',%d', Confidence_mat(pIdx, cIdx) > synergy_threshold);
            fprintf(fd_conf, ',%f', Confidence_mat(pIdx, cIdx));
        end
        if(pIdx ~= numel(pair_idx))
            fprintf(fd_syn, '\n');
            fprintf(fd_conf, '\n');    
        end
    end    
    fclose(fd_syn);
    fclose(fd_conf);

%%
% %% Homologous drug identification
% 
% 
% 
% % Read and match IC50 values
% X = readtable('input/DrugHomology/gdsc_manova_input_w5.csv');
% row_mask = ismember(X.Cosmic_ID, annotations.cellLines.COSMIC);
% GDSC_IC50_table = X(row_mask, 1:144);
% GDSC_IC50_table.Properties.VariableNames(5:end) = cellfun(@(x) x(1:end-6), GDSC_IC50_table.Properties.VariableNames(5:end), 'UniformOutput', false);
% 
% [~, IC50_row_perm] = ismember(GDSC_IC50_table.Cosmic_ID, annotations.cellLines.COSMIC);
% IC50_Z = -Modified_zscore(IC50(IC50_row_perm, :)); IC50_Z(isnan(IC50_Z)) = 0;
% GDSC_IC50_Z = -Modified_zscore(table2array(GDSC_IC50_table(1:end, 5:end))); GDSC_IC50_Z(isnan(GDSC_IC50_Z)) = 0;
% 
% IC50_Sim = IC50_Z'*GDSC_IC50_Z;
% % IC50_Sim_counts = double(logical(IC50_Z'))*double(logical(GDSC_IC50_Z));
% % IC50_Sim_normalized = IC50_Sim ./ IC50_Sim_counts;
% IC50_Sim_normalized = IC50_Sim ./ repmat(sum(double(logical(IC50_Z')), 2), 1, size(GDSC_IC50_Z, 2));
% % IC50_Sim_normalized = IC50_Sim ./ repmat(sum(double(logical(GDSC_IC50_Z)), 1), size(IC50_Z, 2), 1);
% 
% [~, idx] = max(IC50_Sim_normalized, [], 2);
% homoDrugs = GDSC_IC50_table.Properties.VariableNames(idx+4)';





