clear
addpath(genpath('code'));
warning('off','all');    

annotations.cellLines = readtable('input/Dream/molecular/cell_info.csv', 'Delimiter', ',');
annotations.drugs = readtable('input/Dream/synergy/Drugs_mapped.txt', 'Delimiter', '\t');
annotations.drugs.Target = cellfun(@(targets) strsplit(targets, ';'), annotations.drugs.Target, 'UniformOutput', false);

[~, CL_perm] = sort(annotations.cellLines.Tissue__General_);
annotations.cellLines = annotations.cellLines(CL_perm, :);



%% Group cell-lines (first by tissue, and then by their molecular similarity)
if(~exist('input/preprocessed/C2C.mat', 'file'))
    CellLine_distances = cell(3, 1);

    % Tissue-based similarity
    CellLine_distances{1} = ones(size(annotations.cellLines, 1));
    tissue_names = unique(annotations.cellLines.Tissue__General_);
    for i = 1:numel(tissue_names)
        tissue_idx = find(strcmp( annotations.cellLines.Tissue__General_, tissue_names{i}));
        CellLine_distances{1}(tissue_idx, tissue_idx) = 0;
    end
    CellLine_distances{1} = CellLine_distances{1};

    % Expression-based similarity
    [expr_table, cellLine_names, gene_names] = my_tblread('input/Dream/molecular/gex.csv', ',');
    cellLine_names = cellfun(@(x) x(2:end-1), cellLine_names, 'UniformOutput', false);
    gene_names = cellfun(@(x) x(2:end-1), gene_names, 'UniformOutput', false);

    [U,S,V] = svd(expr_table, 'econ');
    adjusted_expr = expr_table - U(:, 1)*S(1,1)*V(:, 1)';

    % [U,S,V] = svd(expr_table, 'econ');
    % adjusted_expr = expr_table - U(:, 1)*S(1,1)*V(:, 1)';

    % [Expr_corr, Expr_corr_pval] = corr(adjusted_expr);
    % Expr_corr_pval(Expr_corr < 0) = 1;
    % Expr_corr_pval(1e-10 < Expr_corr_pval) = 1;
    % Expr_corr_pval(Expr_corr_pval == 0) = min(nonzeros(Expr_corr_pval));
    % Expr_sim = -log10(Expr_corr_pval);
    % 
    % 
    % ind = find(Expr_sim);
    % x = Expr_sim(ind);
    % x = (max(x) - x) ./ (max(x) - min(x));
    % Expr_dist = ones(size(Expr_sim));
    % Expr_dist(ind) = x;

    % Expr_dist = (1 - Expr_sim) ./ 2;

    Expr_Z = Standard_Normalization(expr_table');
    Expr_dist = dist2(Expr_Z, Expr_Z);
    Expr_dist = Expr_dist ./ max(nonzeros(Expr_dist));

    CellLine_distances{2} = ones(size(annotations.cellLines, 1));
    [~, idx] = ismember(cellLine_names, annotations.cellLines.Sanger_Name);
    CellLine_distances{2}(idx, idx) = Expr_dist;
    % HeatMap(CellLine_distances{2})


    % Methylation
    [methyl_table, cellLine_names, gene_names] = my_tblread('input/Dream/molecular/methyl_probe_beta.csv', ',');
    cellLine_names = cellfun(@(x) x(2:end-1), cellLine_names, 'UniformOutput', false);
    gene_names = cellfun(@(x) x(2:end-1), gene_names, 'UniformOutput', false);

    Methyl_Z = Standard_Normalization(methyl_table');
    Methyl_dist = dist2(Methyl_Z, Methyl_Z);
    Methyl_dist = Methyl_dist ./ max(nonzeros(Methyl_dist));

    CellLine_distances{3} = ones(size(annotations.cellLines, 1));
    [~, idx] = ismember(cellLine_names, annotations.cellLines.Sanger_Name);
    CellLine_distances{3}(idx, idx) = Methyl_dist;
    % HeatMap(CellLine_distances{3})


    % Run SNF
    % SNF parameters
    K = 20;%number of neighbors, usually (10~30)
    alpha = 0.5; %hyperparameter, usually (0.3~0.8)
    T = 15; %Number of Iterations, usually (10~20)

    W1 = affinityMatrix(CellLine_distances{1}, K, alpha);
    W2 = affinityMatrix(CellLine_distances{2}, K, alpha);
    W3 = affinityMatrix(CellLine_distances{3}, K, alpha);

    C2C = SNF({W1,W2, W3}, K, T);
    C2C = C2C - diag(diag(C2C));
    C2C = (C2C - min(nonzeros(C2C))) ./ (max(nonzeros(C2C)) - min(nonzeros(C2C)));
    HeatMap(C2C)

    save('input/preprocessed/C2C.mat', 'C2C', 'CellLine_distances');

else
    load('input/preprocessed/C2C.mat');
end
%% Group drugs
D2D = zeros(size(annotations.drugs, 1));
for i = 1:size(annotations.drugs, 1)
    for j = i+1:size(annotations.drugs, 1)
        D2D(i, j) = 100*numel(intersect(annotations.drugs.Target{i}, annotations.drugs.Target{j})) / numel(union(annotations.drugs.Target{i}, annotations.drugs.Target{j}));
    end
end

D2D = max(D2D, D2D');

%% Read Mono therapy
IC50 = inf(size(annotations.cellLines, 1), size(annotations.drugs, 1));
EMax = nan(size(annotations.cellLines, 1), size(annotations.drugs, 1));
H = nan(size(annotations.cellLines, 1), size(annotations.drugs, 1));
Max_C = nan(size(annotations.cellLines, 1), size(annotations.drugs, 1));

T = readtable('input/synergy/ch2_leaderBoard_monoTherapy.csv');
[~, CL_idx] = ismember(T.CELL_LINE, annotations.cellLines.Sanger_Name);
[~, Drug_idx_A] = ismember(T.COMPOUND_A, annotations.drugs.ChallengeName);
[~, Drug_idx_B] = ismember(T.COMPOUND_B, annotations.drugs.ChallengeName);

for i = 1:size(T, 1)
    if( T.IC50_A(i) < IC50(CL_idx(i), Drug_idx_A(i)) )
        IC50(CL_idx(i), Drug_idx_A(i)) = T.IC50_A(i);
        EMax(CL_idx(i), Drug_idx_A(i)) = T.Einf_A(i);
        H(CL_idx(i), Drug_idx_A(i)) = T.H_A(i);        
        Max_C(CL_idx(i), Drug_idx_A(i)) = str2double(T.MAX_CONC_A{i});        
    end
    if( T.IC50_B(i) < IC50(CL_idx(i), Drug_idx_B(i)) )
        IC50(CL_idx(i), Drug_idx_B(i)) = T.IC50_B(i);
        EMax(CL_idx(i), Drug_idx_B(i)) = T.Einf_B(i);
        H(CL_idx(i), Drug_idx_B(i)) = T.H_B(i);        
        Max_C(CL_idx(i), Drug_idx_B(i)) = str2double(T.MAX_CONC_B{i});        
    end    
end

IC50(IC50==inf) = nan;

%% Compute sensitivity score (AUC, atm)
doses = [0,0.00001,0.00003,0.0001,0.0003,0.001
0,0.00003,0.0001,0.0003,0.001,0.003
0,0.0001,0.0003,0.001,0.003,0.01
0,0.0003,0.001,0.003,0.01,0.03
0,0.001,0.003,0.01,0.03,0.1
0,0.003,0.01,0.03,0.1,0.3
0,0.01,0.03,0.1,0.3,1
0,0.03,0.1,0.3,1,3
0,0.1,0.3,1,3,10];

doses_logscale = log10(doses+1);

Drug_sensitivity = nan(size(annotations.cellLines, 1), size(annotations.drugs, 1));

fun = @(a, ic50, emax, h) 100 + ( (emax - 100) ./ (1 + (ic50 ./ a).^h) );

for i = 1:size(annotations.cellLines, 1)
    for j = 1:size(annotations.drugs, 1)
        if( ~isnan(IC50(i, j)) ) % && ~isnan(EMax(i, j)) && ~isnan(H(i, j)))
            current_dose = find(doses(:, end) == Max_C(i, j));
            if(isempty(current_dose))
                fprintf('%d %d %e\n', i, j, Max_C(i, j));
            end
            Drug_sensitivity(i, j) = integral(@(x) fun(x, IC50(i, j), EMax(i, j), H(i, j)), doses_logscale(current_dose, 2), doses_logscale(current_dose, end));
        end
    end
end
Drug_sensitivity = (Drug_sensitivity - nanmax(nonzeros(Drug_sensitivity))) ./ (nanmin(nonzeros(Drug_sensitivity)) - nanmax(nonzeros(Drug_sensitivity)));

%% Homologous drug identification
% Read drug targets
if(~exist('input/DrugHomology/WinDTome.mat', 'file'))
    tic; 
    WinDTome = readtable('input/DrugHomology/WinDTome.txt', 'Delimiter', '\t', 'Format', '%s %s %d %s %s %s %s %s %s %s %d %d'); 
    [WinDTome_drugs, ic, ia] = unique(WinDTome.Drug_ID);

    WinDTome_targets = arrayfun(@(drug_id) unique(WinDTome.Target_Gene_Symbol(ia == drug_id)), 1:numel(WinDTome_drugs), 'UniformOutput', false)';
    drug_homologs = cell(size(annotations.drugs, 1), 1);
    for i = 1:size(annotations.drugs, 1)
        targets = annotations.drugs.Target{i};

    %     target_overlap = cellfun(@(D) numel(intersect(D, targets)) / numel(union(D, targets)), WinDTome_targets);
    %     target_overlap = cellfun(@(D) numel(intersect(D, targets)), WinDTome_targets);
        tic; target_overlap = arrayfun(@(d) nnz(ismember(annotations.drugs.Target{i}, WinDTome_targets{d})), 1:numel(WinDTome_drugs)); toc
        [~, drug_row, drug_overlap] = find(target_overlap);
        if(numel(drug_row) == 0)
            drug_homologs{i} = {};
        else
            homologous_drug_IDs = WinDTome_drugs(drug_row);
            [~, perm] = sort(zscore(drug_overlap), 'descend');
            homologous_drug_IDs = homologous_drug_IDs(perm);
            drug_homologs{i} = homologous_drug_IDs;
        end
    end
    toc
    save('input/DrugHomology/WinDTome.mat', 'WinDTome', 'WinDTome_drugs', 'WinDTome_targets');
else
    load('input/DrugHomology/WinDTome.mat'); 
end


% Read and match IC50 values
X = readtable('input/DrugHomology/gdsc_manova_input_w5.csv');
row_mask = ismember(X.Cosmic_ID, annotations.cellLines.COSMIC);
GDSC_IC50_table = X(row_mask, 1:144);
GDSC_IC50_table.Properties.VariableNames(5:end) = cellfun(@(x) x(1:end-6), GDSC_IC50_table.Properties.VariableNames(5:end), 'UniformOutput', false);

[~, IC50_row_perm] = ismember(GDSC_IC50_table.Cosmic_ID, annotations.cellLines.COSMIC);
IC50_Z = -Modified_zscore(IC50(IC50_row_perm, :)); IC50_Z(isnan(IC50_Z)) = 0;
GDSC_IC50_Z = -Modified_zscore(table2array(GDSC_IC50_table(1:end, 5:end))); GDSC_IC50_Z(isnan(GDSC_IC50_Z)) = 0;

IC50_Sim = IC50_Z'*GDSC_IC50_Z;
% IC50_Sim_counts = double(logical(IC50_Z'))*double(logical(GDSC_IC50_Z));
% IC50_Sim_normalized = IC50_Sim ./ IC50_Sim_counts;
IC50_Sim_normalized = IC50_Sim ./ repmat(sum(double(logical(IC50_Z')), 2), 1, size(GDSC_IC50_Z, 2));
% IC50_Sim_normalized = IC50_Sim ./ repmat(sum(double(logical(GDSC_IC50_Z)), 1), size(IC50_Z, 2), 1);

[~, idx] = max(IC50_Sim_normalized, [], 2);
homoDrugs = GDSC_IC50_table.Properties.VariableNames(idx+4)';





