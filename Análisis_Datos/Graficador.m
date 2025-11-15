function graficas_lora()
clc; clear; close all;

% === Parámetros ===
excelFile     = 'probabilidades_lora.xlsx';
sheetName     = 'Resumen';
floorHeight_m = 4;      % metros por piso
savePng       = true;   % guardar PNGs

% === Leer tabla ===
T = readtable(excelFile, 'Sheet', sheetName);

% Asegurar columna 'Name' con el identificador de la prueba
if ~any(strcmpi(T.Properties.VariableNames, 'Name'))
    T.Name = string(T{:,1});
else
    T.Name = string(T.Name);
end

% Columnas esperadas
need = {'mean_RSSI','mean_SNR','P_joint_kde','DeliveryRate'};
for c = need
    if ~any(strcmpi(T.Properties.VariableNames, c{1}))
        error('No se encontró la columna: %s en la hoja %s.', c{1}, sheetName);
    end
end

% Tipos numéricos
T.mean_RSSI   = double(T.mean_RSSI);
T.mean_SNR    = double(T.mean_SNR);
T.P_joint_kde = double(T.P_joint_kde);
T.DeliveryRate= double(T.DeliveryRate);

% === Etiquetado: SF, payload, distancia ===
[T.SF, T.Payload] = parseSFandPayload(T.Name);
T.Distance_m      = parseDistanceMeters(T.Name, floorHeight_m);

% Filtrar SFs de interés
validSF = ismember(T.SF, ["SF7","SF9","SF10","SFA"]);
T = T(validSF, :);

% DeliveryRate a porcentaje si está en 0..1
if nanmean(T.DeliveryRate(~isnan(T.DeliveryRate))) <= 1
    T.DeliveryRate = 100*T.DeliveryRate;
end

% === Graficar por payload y métrica ===
payloadCats = ["minimo","maximo"]; % etiquetas internas
metricas    = struct( ...
    'DeliveryRate', struct('ylabel','Delivery Rate (%)','file','delivery_rate'), ...
    'mean_RSSI',   struct('ylabel','RSSI (dBm)','file','rssi'), ...
    'mean_SNR',    struct('ylabel','SNR (dB)','file','snr') );

for p = payloadCats
    Tp = T(strcmpi(T.Payload, p), :);
    if isempty(Tp)
        fprintf('No hay datos para payload %s. Se omite.\n', p);
        continue;
    end
    Tp = sortrows(Tp, 'Distance_m'); % ordenar por distancia

    sfList = ["SF7","SF9","SF10","SFA"];

    % --- Delivery Rate ---
    plotMetric(Tp, sfList, 'DeliveryRate', metricas.DeliveryRate.ylabel, ...
               sprintf('Delivery Rate vs Distancia — payload %s', p), ...
               metricas.DeliveryRate.file, savePng);

    % --- RSSI ---
    plotMetric(Tp, sfList, 'mean_RSSI', metricas.mean_RSSI.ylabel, ...
               sprintf('RSSI medio vs Distancia — payload %s', p), ...
               metricas.mean_RSSI.file, savePng);

    % --- SNR ---
    plotMetric(Tp, sfList, 'mean_SNR', metricas.mean_SNR.ylabel, ...
               sprintf('SNR medio vs Distancia — payload %s', p), ...
               metricas.mean_SNR.file, savePng);
end

disp('Listo. Gráficas generadas.');
end


function [SF, Payload] = parseSFandPayload(names)
    names = string(names);
    N = numel(names);
    SF      = strings(N,1);
    Payload = strings(N,1);

    for i=1:N
        s = names(i);

        % SF
        if contains(s, "SFA", 'IgnoreCase', true)
            SF(i) = "SFA";
        else
            tok = regexp(s, 'SF(7|9|10)', 'match', 'once');
            if isempty(tok), SF(i) = ""; else, SF(i) = string(tok); end
        end

        % Payload (detecta PMax / _ma como máximo; Pm / _m como mínimo)
        if contains(s, {'PMax','_ma','_ma2','_PMax'}, 'IgnoreCase', true)
            Payload(i) = "maximo";
        elseif contains(s, {'_Pm','_m','_m2'}, 'IgnoreCase', true)
            Payload(i) = "minimo";
        else
            Payload(i) = ""; % desconocido
        end
    end
end

function D = parseDistanceMeters(names, floorH)
    names = string(names);
    N = numel(names);
    D = nan(N,1);
    for i=1:N
        s = names(i);

        % Distancias horizontales 0,25,50,75
        m = regexp(s, '_(0|25|50|75)($|_|[^0-9])', 'tokens', 'once');
        if ~isempty(m)
            D(i) = str2double(m{1});
            continue;
        end

        % Patrones SFA_25_m / ... (por si aplica)
        m2 = regexp(s, '_(0|25|50|75)_m', 'tokens', 'once');
        if ~isempty(m2)
            D(i) = str2double(m2{1});
            continue;
        end

        % Vertical: Prueba_SF9_Vertical_3_...
        mv = regexp(s, 'Vertical_(\d+)', 'tokens', 'once');
        if ~isempty(mv)
            floors = str2double(mv{1});
            D(i) = floors * floorH;
            continue;
        end
    end
end

function plotMetric(Tp, sfList, fieldName, ylab, titleStr, baseFile, savePng)
    figure('Color','w'); hold on; grid on; box on;

    for k = 1:numel(sfList)
        sf = sfList(k);
        rows = Tp.SF == sf & ~isnan(Tp.Distance_m) & ~isnan(Tp.(fieldName));
        if ~any(rows), continue; end

        x = Tp.Distance_m(rows);
        y = Tp.(fieldName)(rows);

        % Promediar duplicados por distancia (si los hay)
        [xu,~,idx] = unique(x);
        yu = accumarray(idx, y, [], @mean);

        plot(xu, yu, '-o', 'DisplayName', char(sf));
    end

    xlabel('Distancia (m)');
    ylabel(ylab);
    title(titleStr, 'Interpreter', 'none');
    legend('Location','best');
    hold off;

    if savePng
        
        ptag = "minimo";
        if contains(lower(titleStr),'maximo'), ptag = "maximo"; end
        fn = sprintf('%s_%s.png', baseFile, ptag);
        fn = regexprep(fn, '[^a-zA-Z0-9_\.-]', '');
        print(gcf, fn, '-dpng', '-r150');
    end
end

