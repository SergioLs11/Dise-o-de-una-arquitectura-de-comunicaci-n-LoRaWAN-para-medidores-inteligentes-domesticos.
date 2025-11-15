%% Leer datos
T = readtable('Prueba_Descarga_SF8.xlsx', ...
              'VariableNamingRule','preserve');

id    = T.("ID");            % Nº de paquete
v_sf7 = T.("Voltaje_SF7");
v_sf8 = T.("Voltaje_SF8");
v_sf9 = T.("Voltaje_SF9");

% Tiempo equivalente (1 paquete por segundo)
t_seconds = id;
t_days    = t_seconds / (3600);

%% Gráfica principal
figure;

ax1 = axes;                   % eje inferior (paquetes)
plot(id, v_sf7, '-o', 'MarkerSize', 3, 'DisplayName','SF7'); hold on;
plot(id, v_sf8, '-s', 'MarkerSize', 3, 'DisplayName','SF8');
plot(id, v_sf9, '-^', 'MarkerSize', 3, 'DisplayName','SF9');

xlabel(ax1,'Número de paquetes');
ylabel(ax1,'Voltaje [V]');
ylim(ax1,[2.5 4.5]);
grid(ax1,'on');
legend(ax1,'Location','southwest');

% Poner ticks en miles de paquetes
maxID = max(id);
xticks(ax1, 0:10000:maxID);
ax1.XAxis.Exponent = 3;   % muestra ×10^3

%% Eje superior: mismo X, etiquetas en días
ax2 = axes('Position', ax1.Position, ...
           'XAxisLocation','top', ...
           'YAxisLocation','right', ...
           'Color','none', ...
           'XColor','k', ...
           'YColor','none');   % ocultamos Y superior

% El eje superior usa los mismos límites y ticks que el inferior
ax2.XLim   = ax1.XLim;
ax2.XTick  = ax1.XTick;

% Convertimos los ticks (nº de paquetes) a días
t_days_ticks = ax2.XTick / (3600);
ax2.XTickLabel = arrayfun(@(x) sprintf('%.0f',x), t_days_ticks, ...
                          'UniformOutput', false);

xlabel(ax2,'Tiempo [horas]');

% Vinculamos por si luego mueves límites
linkaxes([ax1 ax2],'x');

