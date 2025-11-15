%% probabilidades_lora_kde.m
% Estima probabilidades continuas de RSSI y SNR (univariada y conjunta)

% CONFIG
input_file  = 'pruebas_lora_multi.xlsx';
output_file = 'probabilidades_lora.xlsx';
hoja_excluir = 'tablaPromedios';
umbral_rssi = -100;
umbral_snr  = 0;

% Obtener hojas
[~, sheets] = xlsfinfo(input_file);
sheets = sheets(~strcmpi(sheets, hoja_excluir)); % excluir si existe

% Inicializar resultados
res_hdr = {'Hoja','N_samples','mean_RSSI','mean_SNR', ...
    'P_RSSI_kde','P_SNR_kde','P_joint_kde','DeliveryRate','MaxIDP','LostPackets'};
results = cell(0,length(res_hdr));

fprintf('Procesando %d hojas...\n', length(sheets));

for i = 1:length(sheets)
    sheet = sheets{i};
    try
        T = readtable(input_file, 'Sheet', sheet);
    catch
        fprintf('   No se pudo leer hoja %s.\n', sheet);
        continue
    end

    % Normalizar nombres de columnas
    varnames = lower(T.Properties.VariableNames);

    % Buscar columnas
    idx_rssi = find(strcmp(varnames, 'rssi'), 1);
    idx_snr  = find(strcmp(varnames, 'snr'), 1);
    idx_idp  = find(strcmp(varnames, 'idp'), 1); % fcnt
    idx_id   = find(strcmp(varnames, 'id'), 1); 

    if isempty(idx_rssi) || isempty(idx_snr) || isempty(idx_idp)
        fprintf(' Hoja %s ignorada (falta RSSI/SNR/IDP)\n', sheet);
        continue
    end

    % Extraer y limpiar datos
    rssi = T{:, idx_rssi};
    snr  = T{:, idx_snr};
    idp  = T{:, idx_idp};

    % Remove NaN
    mask_valid = ~(isnan(rssi) | isnan(snr) | isnan(idp));
    rssi = rssi(mask_valid);
    snr  = snr(mask_valid);
    idp  = idp(mask_valid);

    n = length(rssi);
    if n < 5
        fprintf('  Hoja %s tiene muy pocos datos (%d). Se omite.\n', sheet, n);
        continue
    end

    % Estadísticos simples
    mean_rssi = mean(rssi);
    mean_snr  = mean(snr);

    %  KDE univariada para RSSI 
    % elegir grid adaptativo basado en datos
    nx = 512;
    xmin = min(rssi) - 5;
    xmax = max(rssi) + 5;
    xgrid = linspace(xmin, xmax, nx);
    [f_rssi, xi] = ksdensity(rssi, xgrid, 'Function', 'pdf');

    % Probabilidad continua P(RSSI >= umbral)
    mask_tail = xi >= umbral_rssi;
    p_rssi_kde = trapz(xi(mask_tail), f_rssi(mask_tail));

    % ---- KDE univariada para SNR ----
    ny = 512;
    ymin = min(snr) - 5;
    ymax = max(snr) + 5;
    ygrid = linspace(ymin, ymax, ny);
    [f_snr, yi] = ksdensity(snr, ygrid, 'Function', 'pdf');
    mask_tail_snr = yi >= umbral_snr;
    p_snr_kde = trapz(yi(mask_tail_snr), f_snr(mask_tail_snr));

    % ---- KDE conjunta 2D ----
    % Crear malla razonable (no exagerar resolución para memoria)
    nx2 = 150; ny2 = 150;
    x2 = linspace(xmin, xmax, nx2);
    y2 = linspace(ymin, ymax, ny2);
    [X, Y] = meshgrid(x2, y2);
    XY = [X(:) Y(:)];

    % ksdensity multivariada (2D)
    try
        [f2, ~] = ksdensity([rssi snr], XY);
        F2 = reshape(f2, ny2, nx2); % filas->y, cols->x (ksdensity devuelve filas=points)
        % Integración numerica sobre region X>=umbral_rssi & Y>=umbral_snr
        % calcular dx, dy
        dx = x2(2)-x2(1);
        dy = y2(2)-y2(1);
        mask_joint = (X >= umbral_rssi) & (Y >= umbral_snr);
        p_joint_kde = sum(F2(mask_joint)) * dx * dy;
    catch ME
        fprintf('  KDE 2D falló en hoja %s (%s). Se usará aproximación empírica.\n', sheet, ME.message);
        % fallback: probabilidad conjunta empírica discreta
        p_joint_kde = sum((rssi >= umbral_rssi) & (snr >= umbral_snr)) / n;
    end

    % ---- Delivery rate (usando IDP) ----
    max_idp = max(idp);
    total_expected = max_idp - min(idp) + 1;
    total_received = n;
    lost_packets = total_expected - total_received;
    delivery_rate = total_received / total_expected;

    % Guardar fila
    results(end+1, :) = {sheet, n, mean_rssi, mean_snr, p_rssi_kde, p_snr_kde, p_joint_kde, delivery_rate, max_idp, lost_packets};

    % Opcional: guardar plots de PDF (univariados)
    try
        fig = figure('Visible','off');
        subplot(2,1,1);
        plot(xi, f_rssi, 'LineWidth', 1.5); hold on;
        xline(umbral_rssi, 'r--', 'Umbral');
        title(sprintf('%s - PDF RSSI (KDE)', sheet));
        xlabel('RSSI (dBm)'); ylabel('pdf');

        subplot(2,1,2);
        plot(yi, f_snr, 'LineWidth', 1.5); hold on;
        xline(umbral_snr, 'r--', 'Umbral');
        title(sprintf('%s - PDF SNR (KDE)', sheet));
        xlabel('SNR (dB)'); ylabel('pdf');

        saveas(fig, sprintf('PDF_%s.png', sheet));
        close(fig);
    catch
        % no crítico si falla guardar figura
    end

    fprintf('  ✓ Hoja %s: n=%d, P_RSSI=%.4f, P_SNR=%.4f, P_joint=%.4f, Delivery=%.3f\n', ...
        sheet, n, p_rssi_kde, p_snr_kde, p_joint_kde, delivery_rate);
end

% Crear tabla y escribir Excel
if ~isempty(results)
    Tres = cell2table(results, 'VariableNames', res_hdr);
    % Guardar hoja resumen en output_file
    writetable(Tres, output_file, 'Sheet', 'Resumen');
    fprintf('Resultados guardados en: %s (hoja "Resumen")\n', output_file);
else
    fprintf('No se generaron resultados. Verifique hojas y columnas.\n');
end

