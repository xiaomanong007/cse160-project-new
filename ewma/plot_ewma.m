function plot_ewma(node_id_query, neighbor_id_query)
    % PLOT_EWMA Plot link quality vs trials for a specific (node, neighbor) pair.
    %
    % File format:
    %   Line 1: alpha  (e.g. 700)
    %   Rest :  node_id  neighbor_id  num_trials  link_quality
    %
    % Usage:
    %   plot_ewma(3, 17)

    fname = 'ewma_value.txt';

    fid = fopen(fname, 'r');
    if fid == -1
        error('Cannot open file %s', fname);
    end

    % Read alpha (first number in file)
    alpha_scaled = fscanf(fid, '%f', 1);   % e.g., 700

    % Read the remaining data as 4 columns:
    % node_id, neighbor_id, num_trials, link_quality
    data = fscanf(fid, '%f %f %f %f', [4 Inf])';
    fclose(fid);

    if isempty(data)
        error('No EWMA data found in %s', fname);
    end

    node_id    = data(:, 1);
    neigh_id   = data(:, 2);
    num_trials = data(:, 3);
    link_qual  = data(:, 4);

    % Filter rows where BOTH node and neighbor match the query
    idx = (node_id == node_id_query) & (neigh_id == neighbor_id_query);

    if ~any(idx)
        fprintf('No data found for node %d -> neighbor %d\n', ...
                 node_id_query, neighbor_id_query);
        return;
    end

    x = num_trials(idx);
    y = link_qual(idx);

    % Optional: sort by number of trials, in case lines are out of order
    [x, order] = sort(x);
    y = y(order);

    figure;
    plot(x, y, '-o', 'LineWidth', 2);
    grid on;

    xlabel('Number of trials');
    ylabel('Link quality (0–1000)');
    title(sprintf('EWMA link quality: Node %d \\rightarrow Neighbor %d (alpha = %.3f)', ...
                  node_id_query, neighbor_id_query, alpha_scaled/1000));

end
