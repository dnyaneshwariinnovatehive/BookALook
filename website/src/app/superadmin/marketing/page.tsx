'use client';

import React, { useEffect, useState, useMemo } from 'react';
import { PageHeader, Card, Badge, Button, Drawer, Field, EmptyState, Skeleton, Alert, DescriptionList, ui } from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';

interface Variable {
    key: string;
    label: string;
    description: string;
    example: string;
}

interface Automation {
    id: string;
    key: string;
    name: string;
    description: string;
    audience: string;
    frequency_label: string;
    is_enabled: boolean;
    aisensy_campaign_name: string | null;
    lead_time_minutes: number | null;
    variables: Variable[];
    health: {
        status: string;
        last_run_at: string | null;
        last_success_at: string | null;
        last_failure_at: string | null;
    };
}

export default function WhatsappAutomationsPage() {
    const [automations, setAutomations] = useState<Automation[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Editing State
    const [editingAutomation, setEditingAutomation] = useState<Automation | null>(null);
    const [editData, setEditData] = useState<{
        is_enabled: boolean;
        aisensy_campaign_name: string;
        lead_time_minutes: number | null;
    } | null>(null);
    const [isSaving, setIsSaving] = useState(false);

    // Test State
    const [testPhone, setTestPhone] = useState('');
    const [isTesting, setIsTesting] = useState(false);
    const [testStatus, setTestStatus] = useState<{ type: 'success' | 'error', message: string } | null>(null);

    useEffect(() => {
        fetchAutomations();
    }, []);

    const fetchAutomations = async () => {
        setIsLoading(true);
        setError(null);
        try {
            const response = await fetch('/api/proxy/superadmin/whatsapp-automations');
            if (response.ok) {
                const data = await response.json();
                if (data.success) {
                    setAutomations(data.data || []);
                } else {
                    setError(data.message || 'Failed to load automations.');
                }
            } else {
                setError(`API error: ${response.status} ${response.statusText}`);
            }
        } catch (err: any) {
            console.error('Failed to load automations', err);
            setError(err.message || 'Failed to load automations');
        } finally {
            setIsLoading(false);
        }
    };

    const handleEdit = (automation: Automation) => {
        setEditingAutomation(automation);
        setEditData({
            is_enabled: automation.is_enabled,
            aisensy_campaign_name: automation.aisensy_campaign_name || '',
            lead_time_minutes: automation.lead_time_minutes,
        });
        setTestPhone('');
        setTestStatus(null);
    };

    const closeDrawer = () => {
        setEditingAutomation(null);
        setEditData(null);
    };

    const handleSave = async () => {
        if (!editingAutomation || !editData) return;
        setIsSaving(true);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(editData),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                await fetchAutomations();
                closeDrawer();
            } else {
                alert(data.message || 'Failed to update automation.');
            }
        } catch (err: any) {
            alert('Failed to update automation.');
        } finally {
            setIsSaving(false);
        }
    };

    const handleTest = async () => {
        if (!editingAutomation || !testPhone) {
            alert('Please enter a phone number to test.');
            return;
        }

        setIsTesting(true);
        setTestStatus(null);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}/test`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ phone: testPhone }),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                setTestStatus({ type: 'success', message: 'Test message sent successfully.' });
            } else {
                setTestStatus({ type: 'error', message: data.message || 'Failed to send test message.' });
            }
        } catch (err: any) {
            setTestStatus({ type: 'error', message: 'Failed to send test message.' });
        } finally {
            setIsTesting(false);
        }
    };

    const getStatusTone = (status: string) => {
        switch (status) {
            case 'WORKING': return 'success';
            case 'READY': return 'info';
            case 'DISABLED': return 'neutral';
            case 'NOT_CONFIGURED': return 'error';
            case 'NEEDS_ATTENTION': return 'warning';
            case 'FAILING': return 'error';
            default: return 'neutral';
        }
    };

    const getStatusLabel = (status: string) => {
        switch (status) {
            case 'NOT_CONFIGURED': return 'Not Configured';
            case 'NEEDS_ATTENTION': return 'Needs Attention';
            default: return status.charAt(0) + status.slice(1).toLowerCase();
        }
    };

    const configuredCount = useMemo(() => automations.filter(a => a.is_enabled && a.aisensy_campaign_name).length, [automations]);

    return (
        <div>
            <PageHeader
                title="WhatsApp Automations"
                subtitle="Manage automated system WhatsApp messages sent by BookALook."
                actions={!isLoading && automations.length > 0 && (
                    <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>
                        {automations.length} automations • {configuredCount} active
                    </div>
                )}
            />

            {isLoading ? (
                <div style={{ display: 'grid', gap: 20, gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    <Skeleton height={220} radius={12} />
                    <Skeleton height={220} radius={12} />
                </div>
            ) : error ? (
                <Alert tone="error">
                    <strong>Error loading automations</strong><br />
                    {error}
                    <div style={{ marginTop: 12 }}>
                        <Button size="sm" onClick={fetchAutomations}>Retry</Button>
                    </div>
                </Alert>
            ) : automations.length === 0 ? (
                <EmptyState
                    icon="bell"
                    title="No automations configured"
                    hint="System WhatsApp messages will appear here once properly seeded in the database."
                />
            ) : (
                <div style={{ display: 'grid', gap: 20, gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    {automations.map((automation) => (
                        <Card
                            key={automation.key}
                            title={automation.name}
                            subtitle={automation.description}
                            actions={<Badge tone={getStatusTone(automation.health.status) as any}>{getStatusLabel(automation.health.status)}</Badge>}
                        >
                            <div className={ui.cardBody}>
                                <DescriptionList
                                    variant="bordered"
                                    items={[
                                        ['Who', <span key="who" style={{ color: 'var(--text-heading)', fontWeight: 500 }}>{automation.audience}</span>] as [React.ReactNode, React.ReactNode],
                                        ['When', <span key="when" style={{ color: 'var(--text-heading)' }}>{automation.frequency_label}</span>] as [React.ReactNode, React.ReactNode],
                                        ['Campaign', automation.aisensy_campaign_name ? (
                                            <span key="campaign" style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--text-heading)' }}>
                                                <Icon name="checkCircle" size={14} style={{ color: 'var(--success-color)' }} /> {automation.aisensy_campaign_name}
                                            </span>
                                        ) : (
                                            <span key="campaign" style={{ fontStyle: 'italic', color: 'var(--text-muted)' }}>Not configured</span>
                                        )] as [React.ReactNode, React.ReactNode],
                                        ...(automation.variables.length > 0 ? [['Variables', 
                                            <div key="vars" style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                                                {automation.variables.map(v => (
                                                    <span key={v.key} style={{ background: 'var(--bg-muted)', padding: '2px 6px', borderRadius: 4, fontFamily: 'monospace', fontSize: 11, color: 'var(--text-body)', border: '1px solid var(--border-color)' }}>
                                                        {'{'}{v.key}{'}'}
                                                    </span>
                                                ))}
                                            </div>
                                        ] as [React.ReactNode, React.ReactNode]] : [])
                                    ]}
                                />
                                <div style={{ marginTop: 20, display: 'flex', justifyContent: 'flex-end' }}>
                                    <Button variant="secondary" size="sm" onClick={() => handleEdit(automation)}>
                                        Configure
                                    </Button>
                                </div>
                            </div>
                        </Card>
                    ))}
                </div>
            )}

            {editingAutomation && editData && (
                <Drawer
                    open={true}
                    onClose={closeDrawer}
                    title={`Configure ${editingAutomation.name}`}
                    description={editingAutomation.description}
                    footer={
                        <div style={{ display: 'flex', justifyContent: 'space-between', width: '100%' }}>
                            <Button variant="secondary" onClick={closeDrawer}>Cancel</Button>
                            <Button variant="primary" loading={isSaving} onClick={handleSave}>Save Changes</Button>
                        </div>
                    }
                >
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 24, paddingBottom: 24 }}>
                        <div style={{ background: 'var(--bg-muted)', padding: 16, borderRadius: 8, border: '1px solid var(--border-color)' }}>
                            <label style={{ display: 'flex', alignItems: 'flex-start', gap: 12, cursor: editingAutomation.key === 'whatsapp_otp' ? 'not-allowed' : 'pointer' }}>
                                <input
                                    type="checkbox"
                                    checked={editData.is_enabled}
                                    disabled={editingAutomation.key === 'whatsapp_otp'}
                                    onChange={e => setEditData({ ...editData, is_enabled: e.target.checked })}
                                    style={{ width: 18, height: 18, marginTop: 2, accentColor: 'var(--accent-color)' }}
                                />
                                <div>
                                    <div style={{ fontWeight: 600, color: 'var(--text-heading)' }}>Enable Automation</div>
                                    {editingAutomation.key === 'whatsapp_otp' ? (
                                        <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 4 }}>WhatsApp OTP is disabled during development to prevent spam.</div>
                                    ) : (
                                        <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 4 }}>Allow the system to send WhatsApp messages when this event occurs.</div>
                                    )}
                                </div>
                            </label>
                        </div>

                        <Field label="AiSensy Campaign Name" hint="The exact campaign name configured in AiSensy.">
                            <input
                                type="text"
                                style={{ width: '100%', padding: '8px 12px', border: '1px solid var(--border-color)', borderRadius: 6, fontSize: 14, background: 'var(--surface-color)', color: 'var(--text-heading)' }}
                                value={editData.aisensy_campaign_name}
                                onChange={e => setEditData({ ...editData, aisensy_campaign_name: e.target.value })}
                                placeholder="e.g. BAL_CUSTOMER_BIRTHDAY"
                            />
                        </Field>

                        {editingAutomation.key === 'whatsapp_appointment_reminder' && (
                            <Field label="Lead Time (Minutes)" hint="E.g., 120 for 2 hours before appointment.">
                                <input
                                    type="number"
                                    style={{ width: '100%', padding: '8px 12px', border: '1px solid var(--border-color)', borderRadius: 6, fontSize: 14, background: 'var(--surface-color)', color: 'var(--text-heading)' }}
                                    value={editData.lead_time_minutes || ''}
                                    onChange={e => setEditData({ ...editData, lead_time_minutes: parseInt(e.target.value) || 0 })}
                                    min="1"
                                />
                            </Field>
                        )}

                        {editingAutomation.variables.length > 0 && (
                            <div>
                                <h4 style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-heading)', marginBottom: 12 }}>Required Variables (Exact Order)</h4>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                                    {editingAutomation.variables.map((v, i) => (
                                        <div key={v.key} style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: 12, background: 'var(--bg-muted)', borderRadius: 6, border: '1px solid var(--border-color)' }}>
                                            <span style={{ fontWeight: 600, color: 'var(--text-muted)', minWidth: 20 }}>{i + 1}.</span>
                                            <div>
                                                <code style={{ background: 'var(--surface-color)', padding: '2px 6px', borderRadius: 4, fontSize: 13, border: '1px solid var(--border-color)', color: 'var(--text-heading)' }}>
                                                    {'{'}{v.key}{'}'}
                                                </code>
                                                <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 6 }}>
                                                    {v.label} — e.g. {v.example}
                                                </div>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            </div>
                        )}

                        {editingAutomation.key !== 'whatsapp_otp' && editingAutomation.is_enabled && editingAutomation.aisensy_campaign_name && (
                            <div style={{ borderTop: '1px solid var(--border-color)', paddingTop: 24, marginTop: 8 }}>
                                <h4 style={{ fontSize: 14, fontWeight: 600, color: 'var(--text-heading)', marginBottom: 12 }}>Test This Automation</h4>
                                <div style={{ display: 'flex', gap: 12 }}>
                                    <input
                                        type="text"
                                        placeholder="+91XXXXXXXXXX"
                                        value={testPhone}
                                        onChange={e => setTestPhone(e.target.value)}
                                        style={{ flex: 1, padding: '8px 12px', border: '1px solid var(--border-color)', borderRadius: 6, fontSize: 14, background: 'var(--surface-color)', color: 'var(--text-heading)' }}
                                    />
                                    <Button variant="secondary" loading={isTesting} onClick={handleTest}>Send Test</Button>
                                </div>
                                {testStatus && (
                                    <div style={{ marginTop: 12 }}>
                                        <Alert tone={testStatus.type}>{testStatus.message}</Alert>
                                    </div>
                                )}
                            </div>
                        )}
                    </div>
                </Drawer>
            )}
        </div>
    );
}
