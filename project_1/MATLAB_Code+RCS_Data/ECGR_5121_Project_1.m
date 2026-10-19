%% Aircraft-Detection Radar Design Script
clear; 
clc; 
close all;

%% Universal Fixes for Blank/Gray Figure Window Rendering Issues
% Force plots into separate windows to bypass the docked container bug
set(0, 'DefaultFigureWindowStyle', 'normal');
% Disable graphics smoothing to prevent GPU acceleration deadlocks
set(0, 'DefaultFigureGraphicsSmoothing', 'off');

%% 1. Define Radar Parameters
Pt = 1000;          % Transmitter power (W)
f = 10e9;           % Frequency (Hz)
R0 = 20e3;          % Detection range (m)
Pr_min = 1e-13;     % Minimum detectable power (W)
eta_ap = 0.34;      % Aperture efficiency
c = 3e8;            % Speed of light (m/s)

% Mathematical Expression for Wavelength:
% lambda = c / f
lambda = c / f;     % Wavelength (m)

%% 2. Load or Generate RCS Data
excel_file = 'RCS_data.xlsx'; 

if exist(excel_file, 'file')
    % Set 'VariableNamingRule' to 'preserve' to suppress column name warnings
    opts = detectImportOptions(excel_file, 'VariableNamingRule', 'preserve');
    data = readtable(excel_file, opts);
    
    % Force columns into clean, explicit 1D double-precision numeric vectors
    azimuth_deg = double(data{:, 1});
    rcs_input = double(data{:, 2});
    
    % Clear any dangling missing/NaN rows from the Excel array indices
    nan_mask = isnan(azimuth_deg) | isnan(rcs_input);
    azimuth_deg(nan_mask) = [];
    rcs_input(nan_mask) = [];
    
    % Clear imaginary/negative bounds to maintain clean calculation vectors
    % If input is dBsm:  rcs_linear = 10^(rcs_dBsm / 10)
    % If input is linear: rcs_dBsm = 10 * log10(rcs_linear)
    if any(rcs_input < 0)
        rcs_dBsm = rcs_input;
        rcs_dBsm(rcs_dBsm < -40) = -40; % Floor deep drops to protect polarplot
        rcs_linear = 10.^(rcs_dBsm / 10);
    else
        rcs_linear = rcs_input;
        rcs_linear(rcs_linear <= 0) = 1e-5; % Eliminate zero division traps
        rcs_dBsm = 10 * log10(rcs_linear);
    end
else
    % Synthetic data generation for demonstration purposes
    azimuth_deg = (0:1:360)'; 
    rcs_linear = 5 + 4 * cosd(4 * azimuth_deg) + randn(size(azimuth_deg))*0.5;
    rcs_linear(rcs_linear <= 0) = 0.1; 
    rcs_dBsm = 10 * log10(rcs_linear);
end

% Mathematical Expression for Degree to Radian conversion:
% azimuth_rad = azimuth_deg * (pi / 180)
azimuth_rad = deg2rad(azimuth_deg);

%% Question 1: Aircraft RCS Plotting
% a) Cartesian Plot
figure('Name', 'Question 1a: Cartesian RCS');
plot(azimuth_deg, rcs_dBsm, 'b-', 'LineWidth', 1.5);
grid on;
xlabel('Azimuthal Aspect Angle (degrees)');
ylabel('RCS (dBsm)');
title('Aircraft RCS vs. Aspect Angle (Cartesian)');

% b) Polar Plot
figure('Name', 'Question 1b: Polar RCS');
polarplot(azimuth_rad, rcs_dBsm, 'b-', 'LineWidth', 1.5);
title('Aircraft RCS (dBsm) vs. Aspect Angle (Polar)');

%% Question 2: Required Minimum Antenna Gain
% a) Calculate required linear gain from the monostatic radar equation:
% Given Monostatic Radar Equation:
% Pr = (Pt * G^2 * lambda^2 * rcs) / ((4*pi)^3 * R0^4)
%
% Rearranging to isolate the required minimum gain (G_req_linear):
% G_req_linear = sqrt( (Pr_min * (4*pi)^3 * R0^4) / (Pt * lambda^2 * rcs_linear) )
%
% Decibel conversion:
% G_req_dBi = 10 * log10(G_req_linear)

numerator = Pr_min * (4 * pi)^3 * (R0^4);
denominator = Pt * (lambda^2) .* rcs_linear;
G_req_linear = sqrt(numerator ./ denominator);
G_req_dBi = 10 * log10(G_req_linear);

% Plot G_req in Cartesian coordinates
figure('Name', 'Question 2a: Required Gain');
plot(azimuth_deg, G_req_dBi, 'r-', 'LineWidth', 1.5);
grid on;
xlabel('Azimuthal Aspect Angle (degrees)');
ylabel('Required Gain (dBi)');
title('Required Antenna Gain vs. Aspect Angle');

% b) Determine minimum antenna gain for 90% coverage
% Sorting values to calculate the 90th percentile index:
% percentile_index = ceil(0.90 * N)
% G_design_linear = 10^(G_design_dBi / 10)
G_req_sorted = sort(G_req_dBi);
percentile_index = ceil(0.90 * length(G_req_sorted));
G_design_dBi = G_req_sorted(percentile_index);
G_design_linear = 10^(G_design_dBi / 10);

fprintf('--- Question 2 Results ---\n');
fprintf('Required antenna gain for 90%% coverage: %.2f dBi\n\n', G_design_dBi);

% Polar plot of G_req with the 90% coverage threshold circle
figure('Name', 'Question 2b: Polar Gain with Threshold');
polarplot(azimuth_rad, G_req_dBi, 'r-', 'LineWidth', 1.5);
hold on;
% Create a circle representing the design gain matching the size of azimuth_rad
r_circle = G_design_dBi * ones(size(azimuth_rad));
polarplot(azimuth_rad, r_circle, 'k--', 'LineWidth', 2);
title('Required Gain (dBi) and 90% Coverage Threshold');
legend('Required Gain', '90% Coverage Gain Threshold', 'Location', 'best');

%% Question 3: Design the Parabolic Reflector
% Given Aperture Gain Formula:
% G_design_linear = eta_ap * (pi * D / lambda)^2
%
% Rearranging to isolate Diameter (D):
% D = (lambda / pi) * sqrt(G_design_linear / eta_ap)
%
% Reflector Radius (a):
% a = D / 2
%
% Focal Length (fp) given a chosen constraint ratio (fp_over_D < 0.40):
% fp = fp_over_D * D

D = (lambda / pi) * sqrt(G_design_linear / eta_ap);
a = D / 2;

% Choose a valid focal length fraction, e.g., fp/D = 0.35 (which is < 0.40)
fp_over_D = 0.35; 
fp = fp_over_D * D;

fprintf('--- Question 3 Results ---\n');
fprintf('a) Required Reflector Diameter (D): %.3f meters\n', D);
fprintf('b) Reflector Radius (a): %.3f meters\n', a);
fprintf('c) Chosen Focal Length (fp): %.3f meters (fp/D = %.2f)\n\n', fp, fp_over_D);

% Sketch the Parabolic Reflector
figure('Name', 'Question 3: Parabolic Reflector Sketch');
% Parabola standard geometric equation centered along the focal axis:
% y = x^2 / (4 * fp)
x_parabola = linspace(-a, a, 400);
y_parabola = (x_parabola.^2) / (4 * fp);

plot(x_parabola, y_parabola, 'b-', 'LineWidth', 2);
hold on;
grid on;

% Plot focal point at coordinates (X=0, Y=fp)
plot(0, fp, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);

% Draw clean 1D coordinate vectors to represent the focal axis line
plot([0, 0], [0, fp], 'k--', 'LineWidth', 1);

xlabel('Aperture Radius X (meters)');
ylabel('Reflector Depth / Focal Axis Y (meters)');
title('Parabolic Reflector Profile and Focal Point Location');
axis equal;
legend('Reflector Dish', 'Focal Point', 'Focal Axis', 'Location', 'best');
